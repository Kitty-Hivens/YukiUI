"""A live picture of a window that closes under it.

The dock's list of an application's windows draws each one live, and closing
one from that list, or the application closing it itself, closes a window the
shell is copying at that moment. The shell has to live through it.

Hyprland makes no frame for a window already gone when the request for one
arrives, and a shell that went on to destroy that frame was cut off by the
compositor for naming an object it did not have. Run the probe with
WAYLAND_DEBUG=client to see which object a failure names.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchCaptureClosedProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Written by tests/core/test_capture_closed_window.py for a test run, and removed after it.
ShellRoot {
    id: probe

    property string appId: ""
    readonly property var target: ToplevelManager.toplevels.values.find(toplevel => toplevel.appId === probe.appId) ?? null

    PanelWindow {
        anchors.top: true
        anchors.left: true
        implicitWidth: 320
        implicitHeight: 200
        color: "transparent"

        ScreencopyView {
            id: view
            anchors.fill: parent
            captureSource: probe.target
            live: true
            paintCursor: false
        }
    }
    IpcHandler {
        target: "captureClosed"
        function ready(): bool {
            return true;
        }
        function watch(appId: string): void {
            probe.appId = appId;
        }
        function hasPicture(): bool {
            return view.hasContent;
        }
    }
}
"""


@pytest.fixture
def capture(desk):
    shell = Shell(desk.bench, probe=PROBE, source=SOURCE, ready=("captureClosed", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


@pytest.mark.parametrize("kind", ["wayland", "x11"])
def test_the_shell_lives_through_a_captured_window_closing(desk, capture, kind):
    for attempt in range(5):
        window = getattr(desk, kind)()
        window.client()
        capture.call("captureClosed", "watch", window.wm_class)
        wait_until(lambda: capture.call("captureClosed", "hasPicture") == "true", timeout=5,
                   what="the picture of the window")
        # A few frames in, so that one is on its way when the window goes.
        time.sleep(0.3)
        window.close()
        time.sleep(0.5)
        assert capture.process.poll() is None, f"the shell died on attempt {attempt}, see {capture.log}"
