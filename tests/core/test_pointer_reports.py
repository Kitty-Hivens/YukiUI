"""What the shell's panels need from the pointer: press-report says where a
press lands, and layer-refocus gives a panel the pointer that stands still
under it as it appears.

Both only listen to the compositor, so they build against any Hyprland whether
or not the events they listen to still mean the same. Panels close on a press
outside them by the first, and take a click without the mouse being nudged by
the second.
"""

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchPointerReportsProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Written by tests/core/test_pointer_reports.py for a test run, and removed after it.
ShellRoot {
    PanelWindow {
        id: panel
        visible: false
        screen: Quickshell.screens[0]
        color: "#ff0000"
        WlrLayershell.namespace: "quickshell:benchpanel"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        margins { left: 500; top: 300 }
        implicitWidth: 400
        implicitHeight: 300
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
        }
    }
    IpcHandler {
        target: "panelProbe"
        function ready(): bool {
            return true;
        }
        // Not named show: "qs ipc call <target> show" runs nothing at all and
        // still exits as if it had, so the panel never came up.
        function appear(): void {
            panel.visible = true;
        }
        function disappear(): void {
            panel.visible = false;
        }
        function hovered(): bool {
            return area.containsMouse;
        }
    }
}
"""

INSIDE = (700, 450)
NAMESPACE = "quickshell:benchpanel"


@pytest.fixture
def panel(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("panelProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def layer_up(bench) -> bool:
    import json
    return any(layer["namespace"] == NAMESPACE
               for data in json.loads(bench.hyprctl("layers", "-j")).values()
               for layers in data["levels"].values() for layer in layers)


def press_lands(bench, pointer) -> str:
    mark = bench.events.mark()
    pointer.press()
    event = bench.events.wait("pointerpress", since=mark)
    pointer.release()
    return event.data


def test_both_are_loaded(bench):
    listed = bench.hyprctl("plugin", "list")
    assert "press-report" in listed and "layer-refocus" in listed


def test_a_press_on_a_window_is_reported_as_that_window(bench, desk):
    window = desk.wayland()
    x, y = window.client()["at"]
    pointer = desk.pointer()
    pointer.move(x + 50, y + 50)
    assert press_lands(bench, pointer) == f"window,{window.address}"


def test_a_panel_appearing_under_a_still_pointer_gets_it(bench, desk, panel):
    pointer = desk.pointer()
    pointer.move(*INSIDE)
    panel.call("panelProbe", "appear")
    wait_until(lambda: layer_up(bench), what="the panel to be up")
    # The mouse is not moved again from here on.
    wait_until(lambda: panel.call("panelProbe", "hovered") == "true", what="the panel to get the pointer")
    assert press_lands(bench, pointer) == f"layer,{NAMESPACE}"

    panel.call("panelProbe", "disappear")
    wait_until(lambda: not layer_up(bench), what="the panel to go")
    wait_until(lambda: press_lands(bench, pointer) != f"layer,{NAMESPACE}", what="the press to land under where the panel was")
