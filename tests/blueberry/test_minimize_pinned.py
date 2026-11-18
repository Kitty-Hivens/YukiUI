"""A pinned window stays in sight over a window flying into the dock or out of it.

The picture of a window minimised or brought back is drawn on an overlay above
every window, and covered a picture in picture, pinned over everything, until
the flight was over. The overlay now leaves the places of the screen's pinned
windows out.

What is left out is a mask, drawn by a shader the bench's software drawing does
not run, so this asks the animator what it leaves out rather than looking.
"""

import json

import pytest

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchMinimizePinnedProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.blueberry.minimize

// Written by tests/blueberry/test_minimize_pinned.py for a test run, and removed after it.
ShellRoot {
    Component.onCompleted: HyprlandData.windowList
    ExMinimizeAnimator {
        id: animator
    }
    IpcHandler {
        target: "pinnedProbe"
        function ready(): string {
            return "yes";
        }
        function leftOut(screen: string): string {
            return JSON.stringify(animator.pinnedOn(screen));
        }
    }
}
"""


@pytest.fixture
def probe(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("pinnedProbe", "ready"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def left_out(probe):
    return json.loads(probe.call("pinnedProbe", "leftOut", OUTPUT))


def test_the_overlay_leaves_out_where_a_pinned_window_stands(probe, desk):
    bench = desk.bench
    picture = desk.wayland("pip")
    desk.wayland("ordinary")
    target = f'window = "address:{picture.address}"'
    bench.eval(f'hl.dispatch(hl.dsp.window.pin({{ action = "enable", {target} }}))')
    bench.eval(f'hl.dispatch(hl.dsp.window.move({{ {target}, x = 1400, y = 700 }}))')
    client = picture.wait(lambda c: c["pinned"] and c["at"] == [1400, 700], "pinned in the corner")
    expected = [{"x": 1400, "y": 700, "w": client["size"][0], "h": client["size"][1]}]
    # Only the pinned one, in the screen's own coordinates.
    wait_until(lambda: left_out(probe) == expected, what=f"the pinned window's place: {expected}, last {left_out(probe)}")

    bench.eval(f'hl.dispatch(hl.dsp.window.pin({{ action = "disable", {target} }}))')
    wait_until(lambda: left_out(probe) == [], what="nothing left out once it is pinned no more")
