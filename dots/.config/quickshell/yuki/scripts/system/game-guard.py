#!/usr/bin/env python3
"""
Keeps a game the only thing on the machine that matters.

The shell decides when game mode is on and which windows the game is in. This
watches what the rest of the machine does to it, and steps in twice:

  * memory has run out, so the fattest thing that is not the game is killed
  * the game is not getting the processor, so the greediest thing that is not
    the game is frozen until the game is over

Killing and freezing are not the same measure and are not interchangeable.
Memory that is gone is gone: nothing short of a process ending gives it back,
and by the time the machine is swapping the game has already stuttered. A
processor being busy is undone the moment the process holding it stops running,
which is what SIGSTOP does, and SIGCONT puts it back with its tabs, its
scrollback and its unsaved buffer intact. A frozen process also stops touching
its pages, so the kernel pages it out on its own, which gives memory back
without anybody being killed.

It runs beside the shell rather than inside it because the moment it is needed
is the moment the shell is least able to act: a machine deep in swap has the
shell's own event loop waiting on pages of QML, and a watchdog that is asleep
for the same reason as its patient is no watchdog. It reads /proc and a state
file, nothing else, so it neither talks to the compositor nor needs the session
variables that would take.
"""

import errno
import json
import os
import signal
import subprocess
import sys
import time

RUNTIME_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell")
STATE_PATH = os.path.join(RUNTIME_DIR, "game-guard.json")
# What has been frozen, kept on disk as well as in memory. A SIGSTOP outlives
# whoever sent it, so a guard that is killed rather than asked to stop would
# otherwise leave a browser stopped for good with nothing left that knows to
# start it again. Read back at startup, and by the --thaw the unit runs after
# the process is gone however it went.
FROZEN_PATH = os.path.join(RUNTIME_DIR, "game-guard.frozen.json")

CLOCK_TICK = os.sysconf("SC_CLK_TCK")
PAGE_KB = os.sysconf("SC_PAGE_SIZE") // 1024
SELF_UID = os.getuid()

APP_NAME = "Game mode"

# The session itself. Killing any of these ends or maims the session rather than
# freeing anything worth having, and freezing them stops the very thing that
# would show the game. Matched against the name in /proc/<pid>/stat, which the
# kernel cuts at fifteen characters, and against the basename of the executable,
# which it does not, so both spellings of the long ones are here.
PROTECTED_NAMES = frozenset({
    "systemd", "(sd-pam)", "init",
    "Hyprland", "start-hyprland", "launch_compositor.sh", "Xwayland",
    "hypridle", "hyprsunset", "hyprpaper",
    "qs", "quickshell",
    "pipewire", "pipewire-pulse", "wireplumber", "pulseaudio",
    "dbus-broker", "dbus-broker-launch", "dbus-daemon",
    "gnome-keyring-d", "gnome-keyring-daemon",
    "polkitd", "polkit-agent-helper-1",
    "ydotoold", "gamemoded", "earlyoom",
    "sshd", "login", "agetty", "uwsm", "waitpid", "signal-handler.sh",
    "at-spi-bus-laun", "at-spi-bus-launcher", "at-spi2-registryd",
    # The equaliser the sound goes through. It is a few megabytes and it is in
    # the game's own audio path, so it is the one media process that is never a
    # candidate.
    "easyeffects",
    # A fuse mount whose daemon is gone hangs every process that walks into it,
    # including the file dialog the game may open.
    "gvfsd-fuse", "fusermount3",
    # Thirty megabytes whose death takes every windows program on the machine
    # with it, the game included. There is no reading of this that makes it a
    # worthwhile thing to close.
    "wineserver",
})
PROTECTED_PREFIXES = ("systemd-", "xdg-desktop-portal", "xdg-document-portal", "xdg-permission-store")

DEFAULTS = {
    "enable": False,
    "killOnMemory": True,
    "freezeOnCpu": True,
    "raiseOomScores": True,
    "memoryFloor": 0.08,
    "memoryPressure": 20.0,
    "memoryTicks": 2,
    "killGrace": 3,
    "minReclaimMb": 200,
    "cpuStarvation": 0.5,
    "cpuPressure": 25.0,
    "cpuTicks": 5,
    "minCpuShare": 0.3,
    "cooldown": 10,
    "oomScoreAdj": 700,
    "keep": [],
    "dryRun": False,
}


def log(message):
    print(message, flush=True)


def read_text(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return None


class Proc:
    __slots__ = ("pid", "ppid", "sid", "comm", "exe", "cpu", "rss_kb", "starttime", "uid")

    def __init__(self, pid, ppid, sid, comm, cpu, rss_kb, starttime, uid):
        self.pid = pid
        self.ppid = ppid
        self.sid = sid
        self.comm = comm
        self.exe = ""
        self.cpu = cpu
        self.rss_kb = rss_kb
        self.starttime = starttime
        self.uid = uid

    @property
    def names(self):
        return (self.comm, self.exe)

    @property
    def label(self):
        """
        The name to put in front of a person.

        A windows program arrives with its own idea of a path, so the executable
        reads as C:\\users\\... and a notification built from it is unreadable.
        The last component is the name anybody would recognise.
        """
        name = self.exe or self.comm
        if "\\" in name:
            name = name.rsplit("\\", 1)[-1]
        return name


class Group:
    """
    A process and everything under it, taken together.

    Nothing worth acting on is one process. A browser is a parent and a handful
    of content processes that share most of their pages, a terminal is a shell
    and whatever it was told to run, and a game under wine is a tree with a
    server and half a dozen services in it. Killing the parent alone leaves the
    children orphaned and still resident, and reading the parent's own numbers
    says a browser using three gigabytes is using eight hundred megabytes.

    A group is rooted at the highest ancestor that is not itself protected, so
    the tree stops below the session rather than swallowing it, and a group is
    only ever a candidate when nothing protected and nothing of the game's is
    inside it. That second rule is what makes a mistake in the name list above
    harmless: get one wrong and the group grows to include something else that
    is right, and the whole group is refused.
    """

    __slots__ = ("root", "pids", "cpu", "rss_kb", "eligible", "holds_game", "holds_focus")

    def __init__(self, root):
        self.root = root
        self.pids = []
        self.cpu = 0
        self.rss_kb = 0
        self.eligible = True
        self.holds_game = False
        self.holds_focus = False

    @property
    def label(self):
        return self.root.label


class Guard:
    def __init__(self):
        self.config = dict(DEFAULTS)
        self.engaged = False
        self.shell_pid = 0
        self.game_pids = []
        self.focus_pid = 0
        self.state_mtime = None

        self.names_cache = {}
        self.prefix_cache = {}
        self.prev_cpu = {}
        self.prev_sample = None
        self.prev_game_delay = None

        self.mem_streak = 0
        self.cpu_streak = 0
        self.cooldown_until = 0.0

        self.frozen = {}
        self.oom_saved = {}
        self.pending_kill = None
        self.stopping = False

    # ---------------------------------------------------------------- state

    def load_state(self):
        try:
            stamp = os.stat(STATE_PATH).st_mtime_ns
        except OSError:
            if self.engaged:
                # The shell is gone. Whatever was done for the game is undone
                # here rather than left standing, because nothing else will.
                log("[guard] state file gone, standing down")
                self.stand_down()
            self.engaged = False
            self.state_mtime = None
            return
        if stamp == self.state_mtime:
            return
        self.state_mtime = stamp
        raw = read_text(STATE_PATH)
        if raw is None:
            return
        try:
            state = json.loads(raw)
        except ValueError:
            log("[guard] state file is not readable as json, ignoring it")
            return

        config = dict(DEFAULTS)
        for key, value in (state.get("guard") or {}).items():
            if key in config:
                config[key] = value
        self.config = config
        self.game_pids = [int(pid) for pid in (state.get("gamePids") or []) if int(pid) > 1]
        self.focus_pid = int(state.get("focusPid") or 0)
        self.shell_pid = int(state.get("shellPid") or 0)

        engaged = bool(state.get("engaged")) and bool(config["enable"])
        if engaged != self.engaged:
            self.engaged = engaged
            log("[guard] game mode " + ("engaged" if engaged else "over"))
            if engaged:
                self.mem_streak = 0
                self.cpu_streak = 0
                self.cooldown_until = 0.0
            else:
                self.stand_down()

    def stand_down(self):
        self.cancel_pending_kill()
        self.thaw_all()
        self.restore_oom()

    def shell_alive(self):
        """
        Whether the shell that wrote the state file is still running.

        The file says a game is on and the runtime directory outlives whoever
        wrote it, so a shell that died mid-game leaves that standing. Acting on
        it afterwards would mean closing programs on behalf of a game nobody is
        playing, which is the one failure worth checking for every tick rather
        than every write.
        """
        if self.shell_pid <= 1:
            return True
        return os.path.exists("/proc/%d" % self.shell_pid)

    # ------------------------------------------------------------- reading

    def scan(self):
        procs = {}
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            raw = read_text("/proc/%d/stat" % pid)
            if not raw:
                continue
            close = raw.rfind(b")")
            if close < 0:
                continue
            comm = raw[raw.find(b"(") + 1:close].decode("utf-8", "replace")
            fields = raw[close + 2:].split()
            if len(fields) < 22:
                continue
            try:
                uid = os.stat("/proc/%d" % pid).st_uid
            except OSError:
                continue
            # Other people's processes cannot be signalled and are none of this
            # program's business either way.
            if uid != SELF_UID:
                continue
            try:
                proc = Proc(
                    pid=pid,
                    ppid=int(fields[1]),
                    sid=int(fields[3]),
                    comm=comm,
                    cpu=int(fields[11]) + int(fields[12]),
                    rss_kb=int(fields[21]) * PAGE_KB,
                    starttime=int(fields[19]),
                    uid=uid,
                )
            except (ValueError, IndexError):
                continue
            proc.exe = self.executable_name(pid, proc.starttime)
            procs[pid] = proc
        return procs

    def executable_name(self, pid, starttime):
        """
        The name a command line carries, which is the one worth matching on.

        /proc/<pid>/stat cuts the name at fifteen characters, so a portal and a
        keyring daemon both arrive shortened and neither matches what anyone
        would write in a list. Read once per process rather than per tick: it is
        another two files for every process on the machine, and the answer does
        not change while the process lives. The start time is part of the key
        because process ids come round again.
        """
        key = (pid, starttime)
        cached = self.names_cache.get(key)
        if cached is not None:
            return cached
        name = ""
        raw = read_text("/proc/%d/cmdline" % pid)
        if raw:
            first = raw.split(b"\0")[0].decode("utf-8", "replace")
            if first:
                name = os.path.basename(first)
        if not name:
            try:
                name = os.path.basename(os.readlink("/proc/%d/exe" % pid))
            except OSError:
                name = ""
        if len(self.names_cache) > 4096:
            self.names_cache.clear()
        self.names_cache[key] = name
        return name

    def is_protected(self, proc):
        keep = self.config["keep"]
        for name in proc.names:
            if not name:
                continue
            if name in PROTECTED_NAMES or name in keep:
                return True
            if name.startswith(PROTECTED_PREFIXES):
                return True
        return proc.pid == os.getpid()

    def game_tree(self, procs):
        """
        Every process the game is made of.

        Three readings, because on this kind of machine one is not enough.

        Descent from the window's own process covers an ordinary program: the
        launcher script, whatever it started, the helpers under that. The walk
        goes up first, as far as the last ancestor that is not part of the
        session proper, so that killing the script the game was started from is
        as much out of the question as killing the window.

        Session ids cover what descent misses once the parentage is gone. Under
        wine everything is reparented onto the user manager within a moment of
        starting, so the game's window, the loader and the script that set the
        prefix up all report systemd as their parent and share nothing but the
        session they were started in. Measured on this machine: ten processes
        making up one game, every one of them with the same parent as every
        unrelated service.

        The prefix covers the last of them, which do not share even that.
        wineserver and the device hosts each end up in a session of their own. A
        prefix is one windows machine, everything running against it falls over
        together, so everything running against the game's prefix is the game.
        """
        if not self.game_pids:
            return set()

        children = self.children_map(procs)
        protected = {pid for pid, proc in procs.items() if self.is_protected(proc)}

        tree = set()
        for pid in self.game_pids:
            proc = procs.get(pid)
            if proc is None:
                continue
            root = proc
            seen = set()
            while True:
                parent = procs.get(root.ppid)
                if parent is None or parent.pid in seen or parent.pid in protected:
                    break
                seen.add(parent.pid)
                root = parent
            self.collect(root.pid, children, tree)

        # A session holding anything of the session's own is not the game's, or a
        # game started from a terminal would drag the terminal's own session in
        # and a login shell would come out looking like part of a game.
        protected_sids = {procs[pid].sid for pid in protected if pid in procs}
        sids = {procs[pid].sid for pid in tree if pid in procs}
        sids -= protected_sids
        sids.discard(0)
        if sids:
            for proc in procs.values():
                if proc.sid in sids:
                    self.collect(proc.pid, children, tree)

        prefixes = set()
        for pid in list(tree):
            prefix = self.wine_prefix(pid, procs)
            if prefix:
                prefixes.add(prefix)
        if prefixes:
            for proc in procs.values():
                if proc.pid in tree:
                    continue
                if self.wine_prefix(proc.pid, procs) in prefixes:
                    self.collect(proc.pid, children, tree)

        return tree

    def wine_prefix(self, pid, procs):
        """
        Which windows machine a process belongs to, if any.

        Read from the environment it was started with, which cannot change while
        it runs, so one reading per process holds for its whole life. Nothing
        reads this at all unless the game turned out to have a prefix, and then
        it is one small file per process, once.
        """
        proc = procs.get(pid)
        if proc is None:
            return ""
        key = (pid, proc.starttime)
        cached = self.prefix_cache.get(key)
        if cached is not None:
            return cached
        prefix = ""
        raw = read_text("/proc/%d/environ" % pid)
        if raw:
            for item in raw.split(b"\0"):
                if item.startswith(b"WINEPREFIX="):
                    prefix = item[11:].decode("utf-8", "replace")
                    break
        if len(self.prefix_cache) > 4096:
            self.prefix_cache.clear()
        self.prefix_cache[key] = prefix
        return prefix

    @staticmethod
    def children_map(procs):
        children = {}
        for proc in procs.values():
            children.setdefault(proc.ppid, []).append(proc.pid)
        return children

    @staticmethod
    def collect(pid, children, out):
        stack = [pid]
        while stack:
            current = stack.pop()
            if current in out:
                continue
            out.add(current)
            stack.extend(children.get(current, ()))

    def build_groups(self, procs, game_tree):
        children = self.children_map(procs)
        protected = {pid for pid, proc in procs.items() if self.is_protected(proc)}

        roots = []
        for pid, proc in procs.items():
            if pid in protected:
                continue
            parent = procs.get(proc.ppid)
            if parent is None or parent.pid in protected:
                roots.append(pid)

        groups = []
        for root in roots:
            group = Group(procs[root])
            members = set()
            self.collect(root, children, members)
            for pid in members:
                member = procs.get(pid)
                if member is None:
                    continue
                group.pids.append(pid)
                group.rss_kb += member.rss_kb
                group.cpu += member.cpu
                if pid in protected:
                    group.eligible = False
                if pid in game_tree:
                    group.holds_game = True
                if pid and pid == self.focus_pid:
                    group.holds_focus = True
            if group.holds_game:
                group.eligible = False
            groups.append(group)
        return groups

    # ------------------------------------------------------------ measures

    @staticmethod
    def meminfo():
        raw = read_text("/proc/meminfo")
        if not raw:
            return 0, 0
        total = available = 0
        for line in raw.decode("ascii", "replace").splitlines():
            if line.startswith("MemTotal:"):
                total = int(line.split()[1])
            elif line.startswith("MemAvailable:"):
                available = int(line.split()[1])
                break
        return total, available

    @staticmethod
    def pressure(resource):
        raw = read_text("/proc/pressure/%s" % resource)
        if not raw:
            return 0.0
        for line in raw.decode("ascii", "replace").splitlines():
            if line.startswith("some"):
                for part in line.split():
                    if part.startswith("avg10="):
                        try:
                            return float(part[6:])
                        except ValueError:
                            return 0.0
        return 0.0

    @staticmethod
    def run_delay(pids):
        """
        How long the game's threads spent sitting in the run queue, in
        nanoseconds, added up over all of them.

        This is the question asked plainly. Processor pressure across the
        machine says something is waiting somewhere, and a core at a hundred per
        cent says nothing at all about whether the game minds. A thread that was
        ready to run and was not given a core is the whole complaint, and the
        scheduler counts exactly that per thread.
        """
        total = 0
        for pid in pids:
            try:
                tasks = os.listdir("/proc/%d/task" % pid)
            except OSError:
                continue
            for task in tasks:
                raw = read_text("/proc/%d/task/%s/schedstat" % (pid, task))
                if not raw:
                    continue
                parts = raw.split()
                if len(parts) >= 2:
                    try:
                        total += int(parts[1])
                    except ValueError:
                        pass
        return total

    def proportional_kb(self, group):
        """
        What killing a group would actually give back.

        Resident sizes added up over a browser count its shared pages once per
        process, which reads as several gigabytes where two would be freed. The
        proportional figure divides each shared page among the processes holding
        it, so a group's total is the truth. It costs a file per process and is
        only ever read for the few groups already in the running, at the moment
        something is about to be killed.
        """
        total = 0
        found = False
        for pid in group.pids:
            raw = read_text("/proc/%d/smaps_rollup" % pid)
            if not raw:
                continue
            for line in raw.decode("ascii", "replace").splitlines():
                if line.startswith("Pss:"):
                    try:
                        total += int(line.split()[1])
                        found = True
                    except (ValueError, IndexError):
                        pass
                    break
        return total if found else group.rss_kb

    # ------------------------------------------------------------- actions

    def notify(self, title, body, urgency="normal"):
        # A rehearsal says what it would have done in the log. Announcing a
        # browser as closed while it is still running is the one thing a dry run
        # must not do.
        if self.config["dryRun"]:
            return
        try:
            subprocess.Popen(
                ["notify-send", "--app-name=" + APP_NAME, "--urgency=" + urgency, title, body],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass

    def signal_group(self, pids, signum, procs):
        """
        Signals a group, and only if every process in it is still the one that
        was measured.

        Between a group being chosen and a kill landing there is a grace period,
        and a process id is reused the moment the machine is busy enough for any
        of this to be happening. Checking the start time makes that reuse
        harmless: the id may be somebody else's now, and then it is left alone.
        """
        sent = 0
        for pid, starttime in pids:
            if pid <= 1:
                continue
            current = procs.get(pid) if procs else None
            if current is None:
                current = self.read_one(pid)
            if current is None or current.starttime != starttime or current.uid != SELF_UID:
                continue
            if self.config["dryRun"]:
                log("[guard] would send %d to %d (%s)" % (signum, pid, current.label))
                sent += 1
                continue
            try:
                os.kill(pid, signum)
                sent += 1
            except OSError as error:
                if error.errno not in (errno.ESRCH, errno.EPERM):
                    log("[guard] could not signal %d: %s" % (pid, error))
        return sent

    def read_one(self, pid):
        raw = read_text("/proc/%d/stat" % pid)
        if not raw:
            return None
        close = raw.rfind(b")")
        if close < 0:
            return None
        comm = raw[raw.find(b"(") + 1:close].decode("utf-8", "replace")
        fields = raw[close + 2:].split()
        if len(fields) < 22:
            return None
        try:
            uid = os.stat("/proc/%d" % pid).st_uid
        except OSError:
            return None
        try:
            proc = Proc(pid, int(fields[1]), int(fields[3]), comm,
                        int(fields[11]) + int(fields[12]),
                        int(fields[21]) * PAGE_KB, int(fields[19]), uid)
        except (ValueError, IndexError):
            return None
        proc.exe = self.executable_name(pid, proc.starttime)
        return proc

    def kill_group(self, group, procs, freed_kb):
        stamped = [(pid, procs[pid].starttime) for pid in group.pids if pid in procs]
        label = group.label
        log("[guard] %s %s (%d processes, %d MB)" % (
            "would close" if self.config["dryRun"] else "terminating",
            label, len(stamped), freed_kb // 1024))
        # Asked first, so a browser writes its session out and a terminal's shell
        # runs its exit traps. What ignores the request is killed by the timer
        # below, which is the whole difference between this and the kernel doing
        # it.
        self.signal_group(stamped, signal.SIGTERM, procs)
        self.pending_kill = {
            "pids": stamped,
            "deadline": time.monotonic() + max(0, int(self.config["killGrace"])),
            "label": label,
        }
        self.notify(
            "Closed %s" % label,
            "Memory had run out. %d MB was given back to the game." % (freed_kb // 1024),
            urgency="critical",
        )

    def finish_pending_kill(self):
        pending = self.pending_kill
        if pending is None or time.monotonic() < pending["deadline"]:
            return
        self.pending_kill = None
        left = self.signal_group(pending["pids"], signal.SIGKILL, None)
        if left:
            log("[guard] %s did not go on being asked, killed %d" % (pending["label"], left))

    def cancel_pending_kill(self):
        if self.pending_kill is None:
            return
        # Whatever was asked to close is left to finish closing. Cancelling means
        # the second signal is not sent, not that the first one is taken back.
        self.pending_kill = None

    def freeze_group(self, group, procs, share):
        stamped = [(pid, procs[pid].starttime) for pid in group.pids if pid in procs]
        label = group.label
        sent = self.signal_group(stamped, signal.SIGSTOP, procs)
        if not sent:
            return
        if self.config["dryRun"]:
            log("[guard] would have frozen %s (%.1f cores)" % (label, share))
            return
        self.frozen[group.root.pid] = {"pids": stamped, "label": label}
        self.write_frozen()
        log("[guard] froze %s (%d processes, %.1f cores)" % (label, sent, share))
        self.notify(
            "Paused %s" % label,
            "It was taking %.1f cores from the game. It starts again when the game is over."
            % share,
        )

    def thaw(self, root_pid, announce=True):
        entry = self.frozen.pop(root_pid, None)
        if entry is None:
            return
        self.write_frozen()
        self.signal_group(entry["pids"], signal.SIGCONT, None)
        log("[guard] thawed %s" % entry["label"])
        if announce:
            self.notify("Resumed %s" % entry["label"], "Game mode is over.")

    def thaw_all(self, announce=True):
        for root_pid in list(self.frozen):
            self.thaw(root_pid, announce=announce)

    def write_frozen(self):
        payload = {
            str(root): {"pids": entry["pids"], "label": entry["label"]}
            for root, entry in self.frozen.items()
        }
        try:
            os.makedirs(RUNTIME_DIR, mode=0o700, exist_ok=True)
            tmp = FROZEN_PATH + ".new"
            with open(tmp, "w") as handle:
                json.dump(payload, handle)
            os.replace(tmp, FROZEN_PATH)
        except OSError as error:
            log("[guard] could not record what is frozen: %s" % error)

    def load_frozen(self):
        raw = read_text(FROZEN_PATH)
        if not raw:
            return
        try:
            payload = json.loads(raw)
        except ValueError:
            return
        for root, entry in payload.items():
            self.frozen[int(root)] = {
                "pids": [(int(pid), int(start)) for pid, start in entry.get("pids", [])],
                "label": entry.get("label", "?"),
            }

    # ---------------------------------------------------------------- oom

    def apply_oom(self, groups):
        """
        Puts the kernel's own killer in the same order of preference as this one.

        earlyoom and the kernel pick by oom_score, which on this session is
        almost entirely resident size, because everything under the user manager
        starts on the same adjustment. That makes a game with a gigabyte of
        textures a better candidate than most of what is open, and it is picked
        while this program is still counting to two. Raising everything else is
        the only half of this that an unprivileged process can do, since lowering
        an adjustment needs a capability we do not have, but relative order is
        all the kernel reads.
        """
        if self.config["dryRun"]:
            return
        target = str(int(self.config["oomScoreAdj"]))
        for group in groups:
            if not group.eligible:
                continue
            for pid in group.pids:
                if pid in self.oom_saved:
                    continue
                path = "/proc/%d/oom_score_adj" % pid
                previous = read_text(path)
                if previous is None:
                    continue
                previous = previous.strip().decode("ascii", "replace")
                if previous == target:
                    continue
                try:
                    with open(path, "w") as handle:
                        handle.write(target)
                except OSError:
                    continue
                self.oom_saved[pid] = previous

    def restore_oom(self):
        for pid, previous in list(self.oom_saved.items()):
            try:
                with open("/proc/%d/oom_score_adj" % pid, "w") as handle:
                    handle.write(previous)
            except OSError:
                pass
        self.oom_saved.clear()

    # --------------------------------------------------------------- cycle

    def tick(self):
        self.finish_pending_kill()
        if not self.engaged:
            return
        if not self.shell_alive():
            log("[guard] the shell that asked for this is gone, standing down")
            self.engaged = False
            self.stand_down()
            return

        now = time.monotonic()
        procs = self.scan()
        game_tree = self.game_tree(procs)
        groups = self.build_groups(procs, game_tree)

        # A group that came back to life on its own, or whose window the person
        # has just switched to, is not left stopped. Alt-tabbing into a frozen
        # browser would otherwise look exactly like a browser that has crashed.
        for root_pid in list(self.frozen):
            group = next((g for g in groups if g.root.pid == root_pid), None)
            if group is None:
                self.thaw(root_pid, announce=False)
            elif group.holds_focus:
                self.thaw(root_pid)

        if self.config["raiseOomScores"]:
            self.apply_oom(groups)

        elapsed = None
        if self.prev_sample is not None:
            elapsed = now - self.prev_sample
        self.prev_sample = now

        shares = {}
        if elapsed and elapsed > 0:
            for group in groups:
                previous = self.prev_cpu.get(group.root.pid)
                if previous is not None and group.cpu >= previous:
                    shares[group.root.pid] = (group.cpu - previous) / CLOCK_TICK / elapsed
        self.prev_cpu = {group.root.pid: group.cpu for group in groups}

        starving = self.starving(game_tree, elapsed)

        if now < self.cooldown_until:
            return
        if self.config["killOnMemory"] and self.check_memory(groups, procs):
            self.cooldown_until = now + max(1, int(self.config["cooldown"]))
            return
        if self.config["freezeOnCpu"] and starving:
            if self.check_cpu(groups, procs, shares):
                self.cooldown_until = now + max(1, int(self.config["cooldown"]))

    def starving(self, game_tree, elapsed):
        """
        Whether the game is being kept from the processor, counted over a tick.

        With no game to read, the machine's own processor pressure stands in. It
        is the weaker signal of the two, which is why it is the fallback and not
        the measure.
        """
        if not game_tree or not elapsed or elapsed <= 0:
            self.prev_game_delay = None
            if self.pressure("cpu") >= float(self.config["cpuPressure"]):
                self.cpu_streak += 1
            else:
                self.cpu_streak = 0
            return self.cpu_streak >= int(self.config["cpuTicks"])

        delay = self.run_delay(game_tree)
        previous = self.prev_game_delay
        self.prev_game_delay = delay
        if previous is None or delay < previous:
            return False
        # Nanoseconds of queueing per nanosecond of wall clock, which is how many
        # of the game's threads were waiting on average.
        waiting = (delay - previous) / (elapsed * 1e9)
        if waiting >= float(self.config["cpuStarvation"]):
            self.cpu_streak += 1
        else:
            self.cpu_streak = 0
        return self.cpu_streak >= int(self.config["cpuTicks"])

    def check_memory(self, groups, procs):
        total, available = self.meminfo()
        if total <= 0:
            return False
        low = available / total < float(self.config["memoryFloor"])
        squeezed = self.pressure("memory") >= float(self.config["memoryPressure"])
        if not (low or squeezed):
            self.mem_streak = 0
            return False
        self.mem_streak += 1
        if self.mem_streak < int(self.config["memoryTicks"]):
            return False
        self.mem_streak = 0

        candidates = sorted(
            (group for group in groups if group.eligible and group.pids),
            key=lambda group: group.rss_kb,
            reverse=True,
        )[:5]
        floor_kb = max(0, int(self.config["minReclaimMb"])) * 1024
        best = None
        best_kb = 0
        for group in candidates:
            actual = self.proportional_kb(group)
            if actual > best_kb:
                best, best_kb = group, actual
        if best is None or best_kb < floor_kb:
            log("[guard] memory is short and nothing is worth closing for it")
            return False
        self.kill_group(best, procs, best_kb)
        return True

    def check_cpu(self, groups, procs, shares):
        floor = float(self.config["minCpuShare"])
        best = None
        best_share = 0.0
        for group in groups:
            if not group.eligible or group.holds_focus or group.root.pid in self.frozen:
                continue
            share = shares.get(group.root.pid, 0.0)
            if share > best_share:
                best, best_share = group, share
        if best is None or best_share < floor:
            self.cpu_streak = 0
            return False
        self.cpu_streak = 0
        self.freeze_group(best, procs, best_share)
        return True

    def run(self):
        os.makedirs(RUNTIME_DIR, mode=0o700, exist_ok=True)
        self.load_frozen()
        if self.frozen:
            log("[guard] a previous run left %d groups stopped, starting them" % len(self.frozen))
            self.thaw_all(announce=False)

        signal.signal(signal.SIGTERM, self.on_stop)
        signal.signal(signal.SIGINT, self.on_stop)

        while not self.stopping:
            self.load_state()
            try:
                self.tick()
            except Exception as error:  # noqa: BLE001
                # A guard that dies on one unreadable file is worse than one that
                # skips a tick. /proc entries vanish under the reader constantly.
                log("[guard] tick failed: %r" % error)
            time.sleep(1.0 if self.engaged else 2.0)

        self.stand_down()

    def on_stop(self, signum, frame):
        self.stopping = True


def report():
    """
    Prints what the guard sees, and touches nothing.

    The one question worth being able to answer before switching this on is
    which processes it considers fair game, and the answer is not something to
    take on trust from a list of names in a source file. Every group is shown
    with the reason it is or is not a candidate, so a session whose compositor
    somehow ended up in the running says so here rather than the first time
    memory runs out.
    """
    guard = Guard()
    guard.load_state()
    procs = guard.scan()
    game_tree = guard.game_tree(procs)
    groups = guard.build_groups(procs, game_tree)

    print("state file : %s" % STATE_PATH)
    print("game mode  : %s" % ("engaged" if guard.engaged else "off"))
    print("game pids  : %s" % (", ".join(str(pid) for pid in guard.game_pids) or "none"))
    print("game tree  : %d processes" % len(game_tree))
    print("focus pid  : %s" % (guard.focus_pid or "none"))
    print()
    print("%-24s %6s %6s %9s  %s" % ("group", "root", "procs", "rss", "verdict"))
    for group in sorted(groups, key=lambda item: item.rss_kb, reverse=True):
        if group.holds_game:
            verdict = "the game"
        elif not group.eligible:
            verdict = "holds part of the session"
        elif group.holds_focus:
            verdict = "candidate, never frozen while focused"
        else:
            verdict = "candidate"
        print("%-24s %6d %6d %7d M  %s" % (
            group.label[:24], group.root.pid, len(group.pids), group.rss_kb // 1024, verdict))


def thaw_only():
    """
    Starts whatever a previous run left stopped, and nothing else.

    Run by the unit after the process is gone, however it went. A guard that was
    killed outright cannot put anything back itself, and a stopped process has
    no way of noticing that the reason it was stopped no longer exists.
    """
    guard = Guard()
    guard.load_frozen()
    if not guard.frozen:
        return
    log("[guard] starting %d groups left stopped" % len(guard.frozen))
    guard.thaw_all(announce=False)


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if "--thaw" in arguments:
        thaw_only()
    elif "--report" in arguments:
        report()
    else:
        Guard().run()
