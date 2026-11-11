"""The work area an X11 application is told, in _NET_WORKAREA on the root.

An application sizes its first window by it. Hyprland works it out only as the
monitors are arranged: not when the X server starts later, as it does once the
first X11 application asks for it, and not when a dock takes its room or gives
it back. The launcher that showed it opened the size of the whole screen, under
the dock, and Hyprland pushed it up until its top was off the screen. The
minimize plugin keeps the value current.

The bench reserves 52 pixels along the bottom by its monitor rule, and a panel
of the test's own takes 40 along the top as a dock would.
"""

import pytest

from bench.bench import HEIGHT, RESERVED_BOTTOM, SHELL, WIDTH, Bench, wait_until
from bench.shell import Shell
from bench.windows import X11Window

PROBE = SHELL / "benchWorkAreaProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Written by tests/core/test_x11_work_area.py for a test run, and removed after it.
ShellRoot {
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: 40
        exclusiveZone: 40
        color: "black"
    }
    IpcHandler {
        target: "workAreaProbe"
        function ready(): string {
            return "yes";
        }
    }
}
"""


@pytest.fixture(scope="module")
def fresh(tmp_path_factory):
    # A compositor of its own, so the X server starts with the window below,
    # after the monitors were arranged.
    bench = Bench(tmp_path_factory.mktemp("workarea"), rules=SHELL / "environments/blueberry/compositor/rules.lua")
    bench.start()
    yield bench
    bench.stop()


def work_area(window):
    return window.command("workarea")["workarea"]


def test_the_work_area_follows_the_room_a_dock_takes(fresh):
    window = X11Window(fresh, "bench.workarea.first")
    try:
        below = [0, 0, WIDTH, HEIGHT - RESERVED_BOTTOM]
        wait_until(lambda: work_area(window) == below, timeout=4,
                   what=f"the work area as the X server starts: {below}, last {work_area(window)}")

        panel = Shell(fresh, probe=PROBE, source=SOURCE, ready=("workAreaProbe", "ready"))
        try:
            panel.start()
            above = [0, 40, WIDTH, HEIGHT - RESERVED_BOTTOM - 40]
            wait_until(lambda: work_area(window) == above, timeout=4,
                       what=f"the work area once the panel takes its room: {above}, last {work_area(window)}")
        finally:
            panel.stop()
            panel.remove_probe()
        wait_until(lambda: work_area(window) == below, timeout=4,
                   what=f"the work area once the panel has gone: {below}, last {work_area(window)}")
    finally:
        window.close()
