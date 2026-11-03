"""The part of the shell the window tests need, run on the bench.

Placement, snapping, minimising and Alt+Tab, as the experimental environment
builds them, and nothing else: no dock, no panels. Loaded from a probe file written
into the shell's own directory for the run, since a shell file reaches the
others by module name only from there. The probe is ignored by git and left
out when the shell is deployed.
"""

from __future__ import annotations

import os
import signal
import subprocess
from pathlib import Path

from .bench import SHELL, Bench, BenchError, ends_with_the_run, wait_until

PROBE = SHELL / "benchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.experimental.switcher
import qs.experimental.windows

// Written by tests/bench/shell.py for a test run, and removed after it.
ShellRoot {
    // The dock's style, which the placement leaves a gap round windows by.
    // There is no dock here, only its setting. Empty until the config is read:
    // set before that, the file read over it.
    IpcHandler {
        target: "benchConfig"
        function setDockStyle(style: string): string {
            if (!Config.ready)
                return "";
            Config.options.experimental.dock.style = style;
            return Config.options.experimental.dock.style;
        }
    }
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }
    ExPlacement {
        id: placement
    }
    ExSnap {
        placement: placement
    }
    ExSwitcher {}
}
"""


class Shell:
    """A probe of the shell on the bench. By default the window parts above;
    a test of another part brings a probe of its own, named apart, and the
    IPC call that answers once it is up.

    With a bus of its own the probe runs under a session bus started for it,
    and `bus` is that bus's address for the test's own clients. A part that
    takes a name on the bus, the notification server say, would otherwise
    take it from the person's live shell.

    A probe draws in software unless it asks for the graphics card. The bench
    shares the card with the person's session, and a probe's work on it, a
    probe taken down above all, ended in the card's engine being reset, which
    is what takes the session's compositor down with it. Only a test that
    looks at what the card alone draws, a blur say, asks for it."""

    def __init__(self, bench: Bench, probe: Path = PROBE, source: str = SOURCE,
                 ready: tuple[str, ...] = ("placement", "list"), own_bus: bool = False, gpu: bool = False):
        self.bench = bench
        self.probe = probe
        self.source = source
        self.ready = ready
        self.own_bus = own_bus
        self.gpu = gpu
        self.bus = ""
        self.process: subprocess.Popen | None = None
        self.log: Path = bench.root / f"{probe.stem}.log"

    def environment(self) -> dict[str, str]:
        """What a client of this probe runs with: the bench's, on the probe's bus when it has one."""
        env = self.bench.environment()
        if self.bus:
            env["DBUS_SESSION_BUS_ADDRESS"] = self.bus
        return env

    def _probe_environment(self) -> dict[str, str]:
        env = self.bench.environment()
        if not self.gpu:
            env["QT_QUICK_BACKEND"] = "software"
        return env

    def start(self):
        self.probe.write_text(self.source)
        if self.own_bus:
            address = self.bench.root / f"{self.probe.stem}.bus"
            address.unlink(missing_ok=True)
            # In a process group of its own, so the bus and the shell under it
            # go together. The shell ends with the bus, and the bus with the
            # run: a forked child does not keep its parent's death signal.
            self.process = subprocess.Popen(
                ["dbus-run-session", "--", "sh", "-c",
                 'printf %s "$DBUS_SESSION_BUS_ADDRESS" > "$1"; exec setpriv --pdeathsig TERM qs -p "$2"',
                 "probe", str(address), str(self.probe)],
                env=self._probe_environment(), stdout=open(self.log, "a"), stderr=subprocess.STDOUT,
                start_new_session=True, preexec_fn=ends_with_the_run)
            self.bus = wait_until(lambda: address.exists() and address.read_text(), timeout=10, what="the probe's bus")
        else:
            self.process = subprocess.Popen(["qs", "-p", str(self.probe)], env=self._probe_environment(),
                                            stdout=open(self.log, "a"), stderr=subprocess.STDOUT,
                                            preexec_fn=ends_with_the_run)
        # Up once it answers on its socket. One that never does is taken down
        # with its probe: a fixture whose setup raises never reaches its
        # teardown, and the probe stayed in the shell's tree.
        try:
            wait_until(lambda: self._answers(), timeout=20, what="the shell probe to answer")
        except BaseException:
            self.stop()
            self.remove_probe()
            raise

    def _answers(self) -> bool:
        if self.process.poll() is not None:
            raise BenchError(f"the shell probe exited with {self.process.returncode}, see {self.log}")
        result = subprocess.run(["qs", "-p", str(self.probe), "ipc", "call", *self.ready],
                                capture_output=True, text=True, env=self.bench.environment())
        return result.returncode == 0

    def stop(self):
        if not self.process or self.process.poll() is not None:
            return
        if self.own_bus:
            # The group this probe started: the bus, and the shell under it.
            os.killpg(self.process.pid, signal.SIGTERM)
        else:
            self.process.terminate()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            if self.own_bus:
                os.killpg(self.process.pid, signal.SIGKILL)
            else:
                self.process.kill()

    def restart(self):
        self.stop()
        self.start()

    def remove_probe(self):
        self.probe.unlink(missing_ok=True)

    def call(self, target: str, function: str, *args: str) -> str:
        result = subprocess.run(["qs", "-p", str(self.probe), "ipc", "call", target, function, *args],
                                capture_output=True, text=True, env=self.bench.environment())
        if result.returncode != 0:
            raise BenchError(f"ipc {target} {function} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    def errors(self) -> list[str]:
        """What the shell complained of: script errors, and types it could not find."""
        if not self.log.exists():
            return []
        markers = ("TypeError", "ReferenceError", "is not a type", "ERROR")
        # Drawn in software, a live picture of a window has nothing to be
        # drawn with, which it says, and which is the probe's choice.
        expected = () if self.gpu else ("Failed to query render formats: No GL context",)
        return [line for line in self.log.read_text(errors="replace").splitlines()
                if any(m in line for m in markers) and not any(e in line for e in expected)]
