"""The part of the shell the window tests need, run on the bench.

Placement, snapping and minimising, as the experimental environment builds
them, and nothing else: no dock, no panels. Loaded from a probe file written
into the shell's own directory for the run, since a shell file reaches the
others by module name only from there. The probe is ignored by git and left
out when the shell is deployed.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from .bench import SHELL, Bench, BenchError, wait_until

PROBE = SHELL / "benchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.core.services
import qs.experimental.windows

// Written by tests/bench/shell.py for a test run, and removed after it.
ShellRoot {
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
}
"""


class Shell:
    def __init__(self, bench: Bench):
        self.bench = bench
        self.process: subprocess.Popen | None = None
        self.log: Path = bench.root / "shell.log"

    def start(self):
        PROBE.write_text(SOURCE)
        self.process = subprocess.Popen(["qs", "-p", str(PROBE)], env=self.bench.environment(),
                                        stdout=open(self.log, "a"), stderr=subprocess.STDOUT)
        # Up once it answers on its socket.
        wait_until(lambda: self._answers(), timeout=20, what="the shell probe to answer")

    def _answers(self) -> bool:
        if self.process.poll() is not None:
            raise BenchError(f"the shell probe exited with {self.process.returncode}, see {self.log}")
        result = subprocess.run(["qs", "-p", str(PROBE), "ipc", "call", "placement", "list"],
                                capture_output=True, text=True, env=self.bench.environment())
        return result.returncode == 0 and result.stdout.strip().startswith("{")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def restart(self):
        self.stop()
        self.start()

    def remove_probe(self):
        PROBE.unlink(missing_ok=True)

    def call(self, target: str, function: str, *args: str) -> str:
        result = subprocess.run(["qs", "-p", str(PROBE), "ipc", "call", target, function, *args],
                                capture_output=True, text=True, env=self.bench.environment())
        if result.returncode != 0:
            raise BenchError(f"ipc {target} {function} failed: {result.stderr.strip()}")
        return result.stdout.strip()

    def errors(self) -> list[str]:
        """What the shell complained of: script errors, and types it could not find."""
        if not self.log.exists():
            return []
        markers = ("TypeError", "ReferenceError", "is not a type", "ERROR")
        return [line for line in self.log.read_text(errors="replace").splitlines() if any(m in line for m in markers)]
