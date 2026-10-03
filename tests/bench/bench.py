"""The nested compositor the tests run against.

A Hyprland of its own, started for one test run inside the session that runs
the tests, with one headless screen and nothing of the person's own: its
config, state and cache directories are temporary ones, its plugins are
built from this repository into the same place, and the compositor rules are
the experimental environment's own file, read as the shell writes it for the
live session.

The screen is 1920 by 1080 with 52 pixels reserved along the bottom, the room
the dock keeps, so a work area is what it is on a real desktop without a dock
running.
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SHELL = REPO / "dots/.config/quickshell/yuki"
RULES = SHELL / "environments/experimental/compositor/rules.lua"
PLUGINS = ("minimize", "drag-report")

OUTPUT = "BENCH"
WIDTH, HEIGHT = 1920, 1080
RESERVED_BOTTOM = 52


class BenchError(RuntimeError):
    pass


def wait_until(check, timeout: float = 5.0, interval: float = 0.05, what: str = "a condition"):
    """Polls `check` until it returns something true, and returns that."""
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = check()
        if last:
            return last
        time.sleep(interval)
    raise BenchError(f"timed out after {timeout} s waiting for {what}, last seen {last!r}")


@dataclass
class Event:
    at: float
    name: str
    data: str


@dataclass
class EventLog:
    """Everything the compositor says on its event socket, as it says it."""

    events: list[Event] = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def add(self, event: Event):
        with self.lock:
            self.events.append(event)

    def mark(self) -> int:
        with self.lock:
            return len(self.events)

    def since(self, mark: int, name: str | None = None) -> list[Event]:
        with self.lock:
            return [event for event in self.events[mark:] if name is None or event.name == name]

    def wait(self, name: str, since: int = 0, match=None, timeout: float = 5.0) -> Event:
        def found():
            for event in self.since(since, name):
                if match is None or match(event.data):
                    return event
            return None

        return wait_until(found, timeout, what=f"event {name}")


class Bench:
    def __init__(self, root: Path):
        self.root = root
        self.home = root / "home"
        self.build = root / "build"
        self.config_home = root / "config"
        self.state_home = root / "state"
        self.cache_home = root / "cache"
        self.data_home = root / "data"
        self.process: subprocess.Popen | None = None
        self.signature = ""
        self.wayland_display = ""
        self.x_display = ""
        self.events = EventLog()
        self._reader: threading.Thread | None = None
        self._stopping = False

    # Building

    def _build(self):
        self.build.mkdir(parents=True, exist_ok=True)
        builds = [["make", "-s", "-C", str(REPO / "hypr-plugins" / name), f"OUT={self.build / name}.so"] for name in PLUGINS]
        builds.append(["make", "-s", "-C", str(REPO / "tests/bench/pointer"), f"OUT={self.build / 'pointer'}"])
        for command in builds:
            result = subprocess.run(command, capture_output=True, text=True)
            # What the compiler said, which an exit status alone does not.
            if result.returncode != 0:
                raise BenchError(f"{' '.join(command)} failed:\n{result.stdout}{result.stderr}")

    @property
    def pointer_tool(self) -> Path:
        return self.build / "pointer"

    @property
    def environment_rules(self) -> Path:
        """Where a shell started on the bench writes the environment's compositor rules."""
        return self.config_home / "hypr/hyprland/shellOverrides/environment.lua"

    def _config(self) -> Path:
        loads = "\n".join(f'hl.plugin.load("{self.build / name}.so")' for name in PLUGINS)
        text = f"""-- Written by tests/bench/bench.py for one test run.
hl.config({{
    animations = {{ enabled = false }},
    misc = {{ disable_hyprland_logo = true, disable_splash_rendering = true, focus_on_activate = true }},
    -- The bench types through a virtual keyboard that brings a keymap of its
    -- own, whose keycodes mean nothing in the default layout, so binds are
    -- matched by the symbol typed.
    input = {{ resolve_binds_by_sym = true }},
}})
hl.monitor({{ output = "{OUTPUT}", mode = "{WIDTH}x{HEIGHT}@60", position = "0x0", scale = 1, reserved = {{ bottom = {RESERVED_BOTTOM} }} }})
-- The nested compositor's own window on the session it runs in: off, so the
-- headless screen is the only one and nothing shows on the person's desktop.
hl.monitor({{ output = "WAYLAND-1", disabled = true }})
{loads}

-- The experimental environment's rules, with their state kept in this run.
HOME = "{self.home}"
dofile("{RULES}")

-- Where the shell writes the rules of the environment that is up, read as the
-- live config reads it: required, so the compositor watches it, and only when
-- it is there.
local environmentRules = "{self.environment_rules}"
local present = io.open(environmentRules, "r")
if present then
    present:close()
    require(environmentRules)
end
"""
        path = self.root / "hyprland.lua"
        path.write_text(text)
        return path

    # Running

    def environment(self) -> dict[str, str]:
        """What a process started on the bench runs with."""
        env = dict(os.environ)
        env.update({
            "HYPRLAND_INSTANCE_SIGNATURE": self.signature,
            "WAYLAND_DISPLAY": self.wayland_display,
            "DISPLAY": self.x_display,
            "XDG_CONFIG_HOME": str(self.config_home),
            "XDG_STATE_HOME": str(self.state_home),
            "XDG_CACHE_HOME": str(self.cache_home),
        })
        # The home directory and the session bus stay the person's: fonts and
        # icons are found there, and nothing the tests start writes to either.
        # The compositor rules keep their state under the bench's own home,
        # which the config hands them.
        return env

    def start(self):
        for directory in (self.home, self.config_home, self.state_home, self.cache_home, self.data_home):
            directory.mkdir(parents=True, exist_ok=True)
        self._build()
        config = self._config()
        # The compositor keeps its own data, state and cache in the run's
        # folders, not the person's: it writes some of each as it starts.
        env = dict(os.environ, XDG_DATA_HOME=str(self.data_home), XDG_STATE_HOME=str(self.state_home),
                   XDG_CACHE_HOME=str(self.cache_home))
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        self.process = subprocess.Popen(["Hyprland", "-c", str(config)], env=env,
                                        stdout=open(self.root / "hyprland.out", "w"), stderr=subprocess.STDOUT,
                                        start_new_session=True)
        # A start that fails halfway takes down what it started: a fixture
        # whose setup raises never reaches its own teardown, and the nested
        # compositor, in a session of its own, outlived the run.
        try:
            instance = wait_until(self._instance, timeout=15, what="the nested Hyprland to come up")
            self.signature = instance["instance"]
            self.wayland_display = instance["wl_socket"]
            self.hyprctl("output", "create", "headless", OUTPUT)
            wait_until(lambda: any(m["name"] == OUTPUT for m in self.monitors()), what=f"output {OUTPUT}")
            self.x_display = self.lua_value('os.getenv("DISPLAY")')
            self._reader = threading.Thread(target=self._read_events, daemon=True)
            self._reader.start()
            self.focus_output()
        except BaseException:
            self.stop()
            raise

    def _instance(self):
        if self.process.poll() is not None:
            raise BenchError(f"Hyprland exited with {self.process.returncode}, see {self.root / 'hyprland.out'}")
        listing = subprocess.run(["hyprctl", "instances", "-j"], capture_output=True, text=True).stdout
        try:
            instances = json.loads(listing)
        except json.JSONDecodeError:
            return None
        return next((i for i in instances if i["pid"] == self.process.pid), None)

    def stop(self):
        self._stopping = True
        if self.process and self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()

    # Talking to it

    def hyprctl(self, *args: str) -> str:
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=self.signature)
        result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, env=env)
        return result.stdout

    def json(self, what: str):
        return json.loads(self.hyprctl(what, "-j"))

    def eval(self, lua: str):
        answer = self.hyprctl("eval", lua).strip()
        if answer != "ok":
            raise BenchError(f"lua failed: {answer}\n{lua}")

    def lua_value(self, expression: str) -> str:
        """The value of a lua expression, as a string, read through a file."""
        target = self.root / "lua-value"
        target.unlink(missing_ok=True)
        self.eval(f'local f = io.open("{target}", "w") f:write(tostring({expression})) f:close()')
        return target.read_text()

    def clients(self) -> list[dict]:
        return self.json("clients")

    def client(self, address: str) -> dict | None:
        return next((c for c in self.clients() if c["address"] == address), None)

    def monitors(self) -> list[dict]:
        return self.json("monitors")

    def reload(self):
        mark = self.events.mark()
        self.hyprctl("reload")
        self.events.wait("configreloaded", since=mark)

    def focus_output(self):
        self.eval(f'hl.dispatch(hl.dsp.focus({{ monitor = "{OUTPUT}" }}))')

    @property
    def work_area(self) -> tuple[int, int, int, int]:
        return 0, 0, WIDTH, HEIGHT - RESERVED_BOTTOM

    @property
    def geometry_file(self) -> Path:
        return self.home / ".local/state/yuki/window-geometry"

    def remembered(self) -> dict[str, list[str]]:
        """The geometry memory, by key: class, then the title for a shared class."""
        if not self.geometry_file.exists():
            return {}
        entries = {}
        for line in self.geometry_file.read_text().splitlines():
            fields = line.split("\t")
            entries[fields[0]] = fields[1:]
        return entries

    def forget_notifications(self):
        """The notifications a shell on the bench kept, which the next one would load."""
        for kept in self.cache_home.rglob("notifications.json"):
            kept.unlink()

    def forget_geometry(self):
        shutil.rmtree(self.home / ".local/state/yuki", ignore_errors=True)

    def _read_events(self):
        path = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / self.signature / ".socket2.sock"
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(str(path))
        buffer = b""
        while not self._stopping:
            try:
                data = sock.recv(65536)
            except OSError:
                return
            if not data:
                return
            buffer += data
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                name, _, rest = line.decode(errors="replace").partition(">>")
                self.events.add(Event(time.monotonic(), name, rest))
