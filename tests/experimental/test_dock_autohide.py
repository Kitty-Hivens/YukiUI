"""A dock that hides on its own stays while the pointer is over it, and comes
out over the windows, while one that stays is under them.

The dock watched the pointer from an item laid under it, beside its buttons
rather than around them. Over the clock, whose area takes the hover itself,
the item under it was no longer hovered, and the dock slid away from under the
pointer. A floating dock, as it was seen, with the corner button after the clock.
"""

import json
import time

import pytest

from bench.bench import HEIGHT, SHELL, WIDTH, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockAutoHideProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.experimental.dock
import qs.experimental.looks

// Written by tests/experimental/test_dock_autohide.py for a test run, and removed after it.
ShellRoot {
    id: probe
    function setUp() {
        Config.options.experimental.dock.edge = "bottom";
        Config.options.experimental.dock.style = "floating";
        Config.options.experimental.dock.showDesktop = true;
        Config.options.experimental.dock.launcherButton = true;
        Config.options.experimental.dock.autoHide = true;
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                probe.setUp();
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            probe.setUp();
    }
    ExDock {
        id: dock
    }
    IpcHandler {
        target: "autoHideProbe"
        function state(): string {
            const window = dock.docks[0];
            return JSON.stringify({ revealed: window?.revealed ?? false, kept: window?.keepShown ?? false });
        }
        function setAutoHide(on: bool): void {
            Config.options.experimental.dock.autoHide = on;
        }
    }
}
"""


@pytest.fixture
def dock(bench):
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("autoHideProbe", "state"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("autoHideProbe", "state"))


def dock_level(bench) -> str:
    """The layer level the dock is on: "1" under the windows, "2" over them,
    or empty while it is not up yet, so a wait goes on rather than ends."""
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for level, layers in data["levels"].items():
            if any(layer["namespace"] == "quickshell:dock" for layer in layers):
                return level
    return ""


def test_the_dock_is_under_the_windows_unless_it_hides(bench, dock):
    # Hiding on its own, it comes out over the windows, which would cover it.
    wait_until(lambda: dock_level(bench) == "2", what="a hiding dock over the windows")
    # Staying, it is under them, so their menus and a window dragged across
    # it are not covered by it.
    dock.call("autoHideProbe", "setAutoHide", "false")
    try:
        wait_until(lambda: dock_level(bench) == "1", what="a dock that stays under the windows")
    finally:
        dock.call("autoHideProbe", "setAutoHide", "false")


def dock_layer(bench) -> tuple[int, int, int, int]:
    """Where the dock's layer stands. The bench keeps room at the bottom of
    its screen, and the layer stands above that rather than at the edge."""
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            for layer in layers:
                if layer["namespace"] == "quickshell:dock":
                    return layer["x"], layer["y"], layer["w"], layer["h"]
    raise AssertionError("no dock layer")


@pytest.mark.parametrize("spot", ["launcher", "clock"])
def test_dock_stays_while_the_pointer_rests_on_it(bench, desk, dock, spot):
    wait_until(lambda: not state(dock)["revealed"], timeout=5, what="the dock to hide first")
    x, y, w, h = dock_layer(bench)
    pointer = desk.pointer()
    # Down from the middle of the screen to the dock's last row of pixels,
    # which brings it out.
    pointer.move(WIDTH // 2, HEIGHT // 2)
    pointer.glide(x + w // 2, y + h - 1)
    wait_until(lambda: state(dock)["revealed"], timeout=3, what="the dock to come out")
    time.sleep(0.5)
    # Across the plate's middle: the launcher alone in the middle of the
    # dock, the clock just before the corner button at its far end.
    middle = y + h - 8 - 26
    pointer.glide(x + w // 2 if spot == "launcher" else x + w - 40, middle)
    # Whether it means to stay, read every little while. Going to and fro it
    # hid only once a gap in it ran past its delay, which made the hiding
    # itself come and go.
    samples = []
    for _ in range(10):
        time.sleep(0.15)
        samples.append(state(dock))
    assert all(sample["kept"] for sample in samples), f"over the {spot} the dock meant to hide: {samples}"
    assert samples[-1]["revealed"]
