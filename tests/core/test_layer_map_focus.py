"""A layer coming up does not move the keyboard to the window under the pointer.

Since 0.57 a mapped layer simulates pointer motion, so that a surface put under
the pointer learns of it. With focus following the pointer that motion can pick
a window as well, and a toast or a volume display would then take the keyboard
from the window the user went to by key, past the one the pointer rests on.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchLayerMapProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Written by tests/core/test_layer_map_focus.py for a test run, and removed after it.
ShellRoot {
    id: probe
    property bool up: false
    PanelWindow {
        visible: probe.up
        anchors.top: true
        anchors.right: true
        implicitWidth: 120
        implicitHeight: 60
        exclusionMode: ExclusionMode.Ignore
        color: "#40ff0000"
        WlrLayershell.namespace: "bench:toast"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }
    IpcHandler {
        target: "toastProbe"
        function setUp(on: bool): void {
            probe.up = on;
        }
        function state(): string {
            return String(probe.up);
        }
    }
}
"""


@pytest.fixture
def toast(bench, desk):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("toastProbe", "state"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def toast_up(bench) -> bool:
    return any(layer["namespace"] == "bench:toast"
               for monitor in bench.json("layers").values()
               for layers in monitor["levels"].values() for layer in layers)


def stage(bench, desk, follow: int, under_tiled: bool):
    """A window the pointer rests on, and another that has the keyboard."""
    under = desk.wayland(width=500, height=400)
    away = desk.wayland(width=500, height=400)
    bench.eval(f"hl.config({{ input = {{ follow_mouse = {follow} }} }})")
    if under_tiled:
        bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "disable", window = "address:{under.address}" }}))')
        bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{away.address}" }}))')
    time.sleep(0.3)
    bench.eval(f'hl.dispatch(hl.dsp.window.move({{ window = "address:{away.address}", x = 1100, y = 100 }}))')
    if not under_tiled:
        bench.eval(f'hl.dispatch(hl.dsp.window.move({{ window = "address:{under.address}", x = 50, y = 100 }}))')
    time.sleep(0.3)
    pointer = desk.pointer()
    x, y, w, h = under.rect
    pointer.move(x + 20, y + h // 2)
    pointer.move(x + 40, y + h // 2)
    time.sleep(0.2)
    bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{away.address}" }}))')
    wait_until(lambda: desk.active() == away.address, what="the keyboard on the far window")
    return under, away, pointer


@pytest.mark.parametrize("follow,under_tiled", [(1, False), (2, False), (1, True), (2, True)])
def test_a_toast_leaves_the_keyboard_where_it_was(bench, desk, toast, follow, under_tiled):
    under, away, pointer = stage(bench, desk, follow, under_tiled)
    try:
        # Long enough for the hand to count as still.
        time.sleep(0.8)
        toast.call("toastProbe", "setUp", "true")
        wait_until(lambda: toast_up(bench), what="the toast")
        time.sleep(0.4)
        assert desk.active() == away.address, f"the keyboard moved with follow_mouse {follow}, tiled {under_tiled}"
        # The pointer really does stand on the other window, and a hand moving
        # it hands the keyboard over under following focus.
        if follow == 1:
            x, y, w, h = under.rect
            pointer.move(x + 60, y + h // 2)
            pointer.move(x + 80, y + h // 2)
            wait_until(lambda: desk.active() == under.address, what="the keyboard to follow a moved pointer")
    finally:
        toast.call("toastProbe", "setUp", "false")
        bench.eval("hl.config({ input = { follow_mouse = 2 } })")
