"""Fixtures shared by every test: the bench, the shell on it, and a clean desk."""

from __future__ import annotations

import itertools

import pytest

from bench.bench import Bench
from bench.shell import Shell
from bench.windows import Keyboard, Pointer, RealKeys, WaylandWindow, X11Window


@pytest.fixture(scope="session")
def bench(tmp_path_factory):
    bench = Bench(tmp_path_factory.mktemp("bench"))
    bench.start()
    yield bench
    bench.stop()


@pytest.fixture(scope="session")
def shell(bench):
    shell = Shell(bench)
    shell.start()
    yield shell
    shell.stop()
    shell.remove_probe()


_names = itertools.count(1)


class Desk:
    """What one test opens, closed again after it, each window of a class of its own."""

    def __init__(self, bench: Bench, shell: Shell):
        self.bench = bench
        self.shell = shell
        self.windows = []
        self.pointers = []

    def name(self, stem: str) -> str:
        # A valid application id as well: no part of one may start with a digit.
        return f"bench.{stem}.w{next(_names)}"

    def wayland(self, stem: str = "wayland", wm_class: str | None = None, **kwargs) -> WaylandWindow:
        window = WaylandWindow(self.bench, wm_class or self.name(stem), **kwargs)
        self.windows.append(window)
        return window

    def x11(self, stem: str = "x11", wm_class: str | None = None, **kwargs) -> X11Window:
        window = X11Window(self.bench, wm_class or self.name(stem), **kwargs)
        self.windows.append(window)
        return window

    @property
    def keyboard(self) -> Keyboard:
        return Keyboard(self.bench)

    def active(self) -> str:
        """The address of the window that has the keyboard."""
        return next((c["address"] for c in self.bench.clients() if c["focusHistoryID"] == 0), "")

    def pointer(self) -> Pointer:
        pointer = Pointer(self.bench)
        self.pointers.append(pointer)
        return pointer

    def real_keys(self) -> RealKeys:
        keys = RealKeys(self.bench)
        self.pointers.append(keys)
        return keys

    def place(self, window, zone: str):
        self.shell.call("placement", "place", window.address, zone)

    def restore(self, window):
        self.shell.call("placement", "restore", window.address)

    def toggle_maximized(self, window):
        self.shell.call("placement", "toggleMaximized", window.address)

    def placed(self) -> dict:
        import json
        return json.loads(self.shell.call("placement", "list"))

    def close(self):
        for pointer in self.pointers:
            pointer.close()
        for window in self.windows:
            try:
                window.close()
            except Exception:
                window.kill()


@pytest.fixture
def desk(bench, shell):
    # Nothing remembered from an earlier test, and the rules read afresh.
    bench.forget_geometry()
    bench.reload()
    bench.focus_output()
    errors_before = len(shell.errors())
    desk = Desk(bench, shell)
    yield desk
    desk.close()
    errors = shell.errors()[errors_before:]
    assert not errors, "the shell reported errors during the test:\n" + "\n".join(errors)
