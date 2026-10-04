"""Windows and a pointer for the tests to drive on the bench."""

from __future__ import annotations

import json
import select
import subprocess
import sys
import time
from pathlib import Path

from .bench import OUTPUT, Bench, BenchError, wait_until

CLIENTS = Path(__file__).resolve().parent / "clients"


class Window:
    """One window of a client process the test controls through its stdin."""

    kind = ""

    def __init__(self, bench: Bench, wm_class: str, argv: list[str]):
        self.bench = bench
        self.wm_class = wm_class
        self.process = subprocess.Popen(argv, env=bench.environment(), stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        ready = self._read()
        if not ready.get("ready"):
            raise BenchError(f"{wm_class} did not come up: {ready}")
        self.address = wait_until(self._find, what=f"{wm_class} to be a client").get("address")

    def _find(self):
        return next((c for c in self.bench.clients() if c["class"] == self.wm_class), None)

    def _read(self, timeout: float = 10.0) -> dict:
        # A client that hangs is a failure, not a wait.
        readable, _, _ = select.select([self.process.stdout], [], [], timeout)
        if not readable:
            raise BenchError(f"{self.wm_class} did not answer in {timeout} s")
        line = self.process.stdout.readline()
        if not line:
            raise BenchError(f"{self.wm_class} ended")
        return json.loads(line)

    def command(self, line: str) -> dict:
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()
        return self._read()

    def state(self) -> dict:
        return self.command("state")

    def client(self) -> dict:
        client = self.bench.client(self.address)
        if client is None:
            raise BenchError(f"{self.wm_class} is not a client any more")
        return client

    @property
    def rect(self) -> tuple[int, int, int, int]:
        client = self.client()
        return (*client["at"], *client["size"])

    def wait(self, check, what: str, timeout: float = 5.0):
        """Waits for `check(client)` to hold, and returns the client."""
        def seen():
            client = self.bench.client(self.address)
            return client if client and check(client) else None

        try:
            return wait_until(seen, timeout, what=f"{self.wm_class}: {what}")
        except BenchError as error:
            # What the window was like when the wait gave up, which "last seen
            # None" does not say: the faults this catches come and go.
            client = self.bench.client(self.address) or {}
            facts = {key: client.get(key) for key in ("at", "size", "tags", "floating", "fullscreen", "fullscreenClient", "workspace")}
            raise BenchError(f"{error}\n  the window then: {facts}") from None

    def wait_state(self, check, what: str, timeout: float = 5.0) -> dict:
        """Waits for what the application believes of itself to satisfy `check`."""
        def seen():
            state = self.state()
            return state if check(state) else None

        return wait_until(seen, timeout, interval=0.1, what=f"{self.wm_class} to believe {what}")

    def close(self):
        if self.process.poll() is not None:
            return
        mark = self.bench.events.mark()
        try:
            self.command("close")
        except (BenchError, BrokenPipeError, ValueError):
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
        self.bench.events.wait("closewindow", since=mark, match=lambda data: f"0x{data}" == self.address, timeout=5)

    def kill(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()


class WaylandWindow(Window):
    kind = "wayland"

    def __init__(self, bench: Bench, wm_class: str, width: int = 700, height: int = 450, title: str = "",
                 maximized: bool = False):
        super().__init__(bench, wm_class, [sys.executable, str(CLIENTS / "wayland_window.py"), wm_class,
                                           title or wm_class, str(width), str(height),
                                           *(["maximized"] if maximized else [])])


class X11Window(Window):
    kind = "x11"

    def __init__(self, bench: Bench, wm_class: str, x: int = 300, y: int = 200, width: int = 700, height: int = 450,
                 title: str = ""):
        super().__init__(bench, wm_class, [sys.executable, str(CLIENTS / "x11_window.py"), wm_class, title or wm_class,
                                           str(x), str(y), str(width), str(height)])


class Pointer:
    """One pointer device on the bench's screen, held for a whole test."""

    def __init__(self, bench: Bench):
        self.process = subprocess.Popen([str(bench.pointer_tool), OUTPUT], env=bench.environment(),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        if self.process.stdout.readline().strip() != "ready":
            raise BenchError("the pointer did not come up")
        self.x = self.y = 0

    def _send(self, line: str):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()
        # A pointer that hangs is a failure, not a wait, as for the clients.
        readable, _, _ = select.select([self.process.stdout], [], [], 5.0)
        if not readable:
            raise BenchError(f"the pointer did not answer {line}")
        answer = self.process.stdout.readline().strip()
        if answer != "ok":
            raise BenchError(f"the pointer refused {line}: {answer}")

    def move(self, x: int, y: int):
        self.x, self.y = x, y
        self._send(f"move {x} {y}")

    def press(self, button: str = "left"):
        self._send(f"press {button}")

    def release(self, button: str = "left"):
        self._send(f"release {button}")

    def glide(self, x: int, y: int, step: int = 6, pause: float = 0.008):
        """Moves in small steps, as a hand does, rather than jumping there."""
        from_x, from_y = self.x, self.y
        distance = max(abs(x - from_x), abs(y - from_y))
        steps = max(1, distance // step)
        for i in range(1, steps + 1):
            self.move(round(from_x + (x - from_x) * i / steps), round(from_y + (y - from_y) * i / steps))
            time.sleep(pause)

    def click(self, x: int, y: int, button: str = "left"):
        """A click as a mouse makes it: the pointer drifts a pixel between press and release."""
        self.move(x, y)
        self.press(button)
        time.sleep(0.03)
        self.move(x + 1, y + 1)
        self.release(button)

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()


class Keyboard:
    """Typing on the bench, through wtype's virtual keyboard.

    Each call is one virtual keyboard from first key to last, so a key held in
    one call is still held through the rest of it. A modifier is held as a real
    keyboard holds it, its key pressed and its state set:
    `hold("Alt_L", "alt")` before and `let_go("Alt_L", "alt")` after.
    """

    def __init__(self, bench: Bench):
        self.bench = bench

    def type(self, *steps: str):
        subprocess.run(["wtype", *steps], env=self.bench.environment(), check=True)

    @staticmethod
    def hold(key: str, modifier: str) -> list[str]:
        return ["-P", key, "-M", modifier]

    @staticmethod
    def let_go(key: str, modifier: str) -> list[str]:
        return ["-m", modifier, "-p", key]

    @staticmethod
    def tap(key: str) -> list[str]:
        return ["-k", key]

    @staticmethod
    def wait(milliseconds: int) -> list[str]:
        return ["-s", str(milliseconds)]
