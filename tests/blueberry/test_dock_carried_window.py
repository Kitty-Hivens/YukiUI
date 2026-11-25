"""The dock's buttons as a window is taken along to another workspace.

The workspace on screen and where each window is are told apart, one after the
other, and a window taken along was for a moment on neither: its button went
and came back, and the row moved over and back with it.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockCarryProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry.dock

// Written by tests/blueberry/test_dock_carried_window.py for a test run, and removed after it.
ShellRoot {
    id: probe

    // Every list of buttons the dock has drawn, as the windows they stand for.
    property var seen: []

    ExDock {
        id: dock
    }
    Connections {
        target: dock.docks[0] ?? null
        function onButtonsChanged() {
            probe.seen = [...probe.seen, dock.docks[0].buttons.map(button => `${button.key}:${button.windows.length}`).join(" ")];
        }
    }
    IpcHandler {
        target: "dockCarry"
        function ready(): bool {
            return Config.ready && dock.docks.length > 0;
        }
        function nothingPinned(): void {
            Config.options.dock.pinnedApps = [];
        }
        function forget(): void {
            probe.seen = [];
        }
        function seen(): string {
            return JSON.stringify(probe.seen);
        }
        function now(): string {
            return (dock.docks[0]?.buttons ?? []).map(button => `${button.key}:${button.windows.length}`).join(" ");
        }
    }
}
"""


@pytest.fixture
def dock(desk):
    shell = Shell(desk.bench, probe=PROBE, source=SOURCE, ready=("dockCarry", "ready"), own_bus=True)
    try:
        shell.start()
        wait_until(lambda: shell.call("dockCarry", "ready") == "true", what="the dock to come up")
        shell.call("dockCarry", "nothingPinned")
        yield shell
    finally:
        desk.bench.eval("hl.dispatch(hl.dsp.focus({ workspace = 1 }))")
        shell.stop()
        shell.remove_probe()


def shows(shell, *classes) -> bool:
    return shell.call("dockCarry", "now").split() == [f"{name.lower()}:1" for name in classes]


def carry(desk, window, workspace: int):
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.move({{ workspace = {workspace}, window = "address:{window.address}" }}))')


def test_a_window_taken_along_keeps_its_button(dock, desk):
    window = desk.wayland()
    wait_until(lambda: shows(dock, window.wm_class), what="its button")
    time.sleep(0.5)
    for workspace in (2, 3, 2, 1):
        dock.call("dockCarry", "forget")
        carry(desk, window, workspace)
        wait_until(lambda: window.client()["workspace"]["id"] == workspace, what="the window to be there")
        time.sleep(0.5)
        assert shows(dock, window.wm_class)
        # Nothing changed, so nothing was drawn again.
        assert json.loads(dock.call("dockCarry", "seen")) == [], f"to workspace {workspace}"


def test_one_left_behind_goes_in_one_step(dock, desk):
    left = desk.wayland()
    taken = desk.wayland()
    wait_until(lambda: shows(dock, left.wm_class, taken.wm_class), what="both buttons")
    time.sleep(0.5)
    dock.call("dockCarry", "forget")
    carry(desk, taken, 2)
    wait_until(lambda: shows(dock, taken.wm_class), what="the one taken along alone")
    time.sleep(0.4)
    assert json.loads(dock.call("dockCarry", "seen")) == [f"{taken.wm_class.lower()}:1"]


def test_a_workspace_switched_to_shows_its_own(dock, desk):
    here = desk.wayland()
    there = desk.wayland()
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.move({{ workspace = 2, follow = false, window = "address:{there.address}" }}))')
    wait_until(lambda: shows(dock, here.wm_class), what="the one here")
    time.sleep(0.4)
    dock.call("dockCarry", "forget")
    desk.bench.eval("hl.dispatch(hl.dsp.focus({ workspace = 2 }))")
    wait_until(lambda: shows(dock, there.wm_class), what="the one there")
    time.sleep(0.4)
    assert json.loads(dock.call("dockCarry", "seen")) == [f"{there.wm_class.lower()}:1"]


def test_a_window_closed_goes_at_once(dock, desk):
    window = desk.wayland()
    wait_until(lambda: shows(dock, window.wm_class), what="its button")
    window.close()
    wait_until(lambda: shows(dock), what="no buttons", timeout=2)
