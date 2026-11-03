"""The button a flyout came out of takes a second click across all of it.

A flyout's window is larger than its plate, by the room for its shadow, and
that room lies over the top of the dock. Only the plate is to take the
pointer: when the rest did, the top of the clock was dead while the
notifications were open, and a click there did not close them.
"""

import time

import pytest

from bench.bench import HEIGHT, SHELL, WIDTH, wait_until
from bench.shell import Shell

from .test_dock_autohide import dock_layer

PROBE = SHELL / "benchDockOpenerProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_dock_opener_clicks.py for a test run, and removed after it.
ShellRoot {
    id: probe
    function setUp() {
        Config.options.blueberry.dock.edge = "bottom";
        Config.options.blueberry.dock.style = "STYLE";
        Config.options.blueberry.dock.showDesktop = true;
        Config.options.blueberry.dock.autoHide = false;
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
    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }
    IpcHandler {
        target: "openerProbe"
        function open(): bool {
            return ExStates.openPopup !== null;
        }
        // The middle of the status icons, along the dock, in its window.
        function statusX(): real {
            const status = probe.find(dock.docks[0]?.contentItem, item => item.statusButton !== undefined && item.clockButton !== undefined);
            const button = status?.statusButton;
            return button ? button.mapToItem(null, button.width / 2, 0).x : -1;
        }
    }
}
"""


@pytest.fixture(params=["floating", "attached"])
def dock(bench, request):
    bench.forget_notifications()
    probe = SHELL / f"benchDockOpener{request.param.capitalize()}Probe.qml"
    shell = Shell(bench, probe=probe, source=SOURCE.replace("STYLE", request.param), ready=("openerProbe", "open"), own_bus=True)
    try:
        shell.start()
        yield shell, request.param
    finally:
        shell.stop()
        shell.remove_probe()


def is_open(shell) -> bool:
    return shell.call("openerProbe", "open") == "true"


@pytest.mark.parametrize("height", ["top", "bottom"])
def test_a_second_click_on_the_clock_closes_the_notifications(bench, desk, dock, height):
    shell, style = dock
    time.sleep(1.0)
    x, y, w, h = dock_layer(bench)
    gap = 8 if style == "floating" else 0
    plate_top = y + h - gap - 52
    # The clock stands just before the corner button at the dock's far end.
    clock_x = x + w - gap - 30
    pointer = desk.pointer()
    pointer.move(WIDTH // 2, HEIGHT // 2)
    pointer.click(clock_x, plate_top + 26)
    wait_until(lambda: is_open(shell), what="the notifications to open")
    time.sleep(0.8)
    # The second click, on the top or the bottom part of the clock.
    pointer.click(clock_x, plate_top + (6 if height == "top" else 46))
    wait_until(lambda: not is_open(shell), timeout=3, what=f"a click on the {height} of the clock to close them")


@pytest.mark.parametrize("which", ["clock", "status"])
def test_a_second_click_without_moving_closes_what_the_first_opened(bench, desk, dock, which):
    # A flyout's window reaches over the top of the dock, and as it appeared
    # under a pointer standing there it was given the pointer, which only a
    # movement took back: the second click in the same place went to the
    # flyout's empty edge and was lost.
    shell, style = dock
    time.sleep(1.0)
    x, y, w, h = dock_layer(bench)
    gap = 8 if style == "floating" else 0
    plate_top = y + h - gap - 52
    # The clock just before the corner button, the status icons asked of the
    # dock, as their width follows the glyphs.
    spot_x = x + w - gap - 30 if which == "clock" else x + round(float(shell.call("openerProbe", "statusX")))
    pointer = desk.pointer()
    pointer.move(WIDTH // 2, HEIGHT // 2)
    pointer.move(spot_x, plate_top + 6)
    pointer.press()
    pointer.release()
    wait_until(lambda: is_open(shell), what=f"the {which} to open its flyout")
    time.sleep(0.8)
    pointer.press()
    pointer.release()
    wait_until(lambda: not is_open(shell), timeout=3, what="a second click on the same spot to close it")
