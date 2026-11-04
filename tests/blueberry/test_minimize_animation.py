"""Minimising with the picture flying into the dock and back.

The picture is drawn on an overlay over the whole screen, which must go once
the flight is over: left behind, it held the window's last picture over the
window come back, which looked like a window that had stopped drawing.

On the card, since a picture of a window is a screen copy, which the
software scene graph has nothing to draw with.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchMinimizeAnimationProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.blueberry.dock
import qs.blueberry.minimize

// Written by tests/blueberry/test_minimize_animation.py for a test run, and removed after it.
ShellRoot {
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }
    ExMinimizeAnimator {
        id: animator
    }
    Binding {
        target: Minimize
        property: "animator"
        value: animator
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.blueberry.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.blueberry.dock.edge = "bottom";
    }
    ExDock {}
    IpcHandler {
        target: "animationProbe"
        function ready(): bool {
            return Config.ready;
        }
        function flights(): int {
            return animator.flights.length;
        }
    }
}
"""


@pytest.fixture
def animated(bench):
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("animationProbe", "ready"), gpu=True)
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def overlay_up(bench) -> bool:
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            if any(layer["namespace"] == "quickshell:minimize" for layer in layers):
                return True
    return False


def test_the_overlay_goes_once_the_window_has_flown(bench, desk, animated):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    # The dock has its button by now, to fly into.
    time.sleep(1.5)

    animated.call("minimize", "toggle", window.address)
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    # Down on its own, before the deadline that brings a stuck one down.
    wait_until(lambda: animated.call("animationProbe", "flights") == "0", timeout=1.8, what="the flight into the dock to end")
    wait_until(lambda: not overlay_up(bench), timeout=3, what="the overlay to go after minimising")

    animated.call("minimize", "toggle", window.address)
    window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")
    wait_until(lambda: animated.call("animationProbe", "flights") == "0", timeout=1.8, what="the flight out of the dock to end")
    wait_until(lambda: not overlay_up(bench), timeout=3, what="the overlay to go after restoring")
