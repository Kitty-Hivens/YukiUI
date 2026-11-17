"""The dock on a screen that has just appeared.

A dock is made for a screen as soon as the screen shows up, which can be
before Quickshell has the Hyprland monitor for it. The workspace the dock
shows was worked out from a call that answered null then, and a binding made
of a call is not evaluated again when the monitor arrives: switched from one
monitor to another, the dock stayed on no workspace at all and showed no
applications. It follows the monitor once there is one.
"""

import json
import time

import pytest

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockNewScreenProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_dock_new_screen.py for a test run, and removed after it.
ShellRoot {
    id: probe

    ExDock {}

    // Bound before the screen exists, the way a window made early is.
    readonly property int secondId: HyprlandData.monitorFor({ name: "SECOND" })?.id ?? -1

    IpcHandler {
        target: "newScreenProbe"
        function secondId(): int {
            return probe.secondId;
        }
        function docks(): string {
            return JSON.stringify(ExStates.dockWindows.map(dock => ({
                screen: dock.screen?.name ?? "",
                workspace: dock.workspaceId,
                apps: dock.appList.filter(app => app.windows.length > 0).map(app => app.appId)
            })));
        }
    }
}
"""


@pytest.fixture
def dock(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dock", "activate", "99"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        # The bench is shared by the tests after this one: its screen back as
        # its config has it, and the second one gone.
        bench.reload()
        bench.hyprctl("output", "remove", "SECOND")
        wait_until(lambda: [m["name"] for m in bench.monitors()] == [OUTPUT], what="the bench's own screen back alone")
        bench.focus_output()


def docks(shell):
    return json.loads(shell.call("newScreenProbe", "docks") or "[]")


def test_the_dock_on_a_screen_switched_to_shows_its_workspace(bench, desk, dock):
    window = desk.wayland("newscreen")
    app = window.client()["class"].lower()
    wait_until(lambda: any(app in d["apps"] for d in docks(dock)), what="the window on the dock of the first screen")
    assert dock.call("newScreenProbe", "secondId") == "-1"

    bench.hyprctl("output", "create", "headless", "SECOND")
    bench.eval('hl.monitor({ output = "SECOND", mode = "1920x1080@60", position = "0x0", scale = 1 })')
    second = wait_until(lambda: next((m["id"] for m in bench.monitors() if m["name"] == "SECOND"), None), what="the second screen")
    # Which comes first, the screen or the monitor, is a race the dock lost
    # now and then. Asked of a screen that was not there yet, the answer has
    # to come once it is, whichever order they come in.
    wait_until(lambda: dock.call("newScreenProbe", "secondId") == str(second),
               what="the monitor of a screen asked about before it existed")
    time.sleep(1.0)
    bench.eval(f'hl.monitor({{ output = "{OUTPUT}", disabled = true }})')
    wait_until(lambda: [m["name"] for m in bench.monitors()] == ["SECOND"], what="the first screen gone")
    bench.eval(f'hl.dispatch(hl.dsp.focus({{ workspace = "{window.client()["workspace"]["id"]}" }}))')

    def settled():
        shown = next(m["activeWorkspace"]["id"] for m in bench.monitors() if m["name"] == "SECOND")
        on_second = [d for d in docks(dock) if d["screen"] == "SECOND"]
        return on_second and on_second[0]["workspace"] == shown and app in on_second[0]["apps"]

    wait_until(settled, timeout=10, what="the dock of the new screen on its workspace with the window")
