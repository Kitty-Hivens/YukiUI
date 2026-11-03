"""The scales the display page offers are the ones Hyprland runs.

Hyprland runs a scale only when it leaves the screen a whole number of points
across and down, and otherwise picks the nearest one that does, without a
word. The page offered 175% on a 1080p screen, which ran at another scale.
It now works out what Hyprland will pick, and this checks it against
Hyprland itself, mode by mode.
"""

import time

import pytest

from bench.bench import HEIGHT, OUTPUT, SHELL, WIDTH, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDisplayPageProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.settings

// Written by tests/core/test_display_scales.py for a test run, and removed after it.
ShellRoot {
    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        DisplayPage {
            id: page
        }
    }
    IpcHandler {
        target: "displayPageProbe"
        function cleanScale(width: int, height: int, scale: real): string {
            return String(page.cleanScale(width, height, scale));
        }
    }
}
"""


@pytest.fixture
def page(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("displayPageProbe", "cleanScale", "1920", "1080", "1"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval(f'hl.monitor({{ output = "{OUTPUT}", mode = "{WIDTH}x{HEIGHT}@60", position = "0x0", scale = 1 }})')
        wait_until(lambda: bench.monitors()[0]["width"] == WIDTH, what="the bench screen back")


def settled_scale(bench, width) -> float:
    """The scale the screen runs at once the change has landed: the same
    reading twice, a moment apart, at the mode asked for."""
    readings = []

    def steady():
        monitor = bench.monitors()[0]
        readings.append((monitor["width"], monitor["scale"]))
        return len(readings) >= 2 and readings[-1] == readings[-2] and readings[-1][0] == width

    time.sleep(0.3)
    wait_until(lambda: steady() or time.sleep(0.2), what=f"the screen to settle at {width}")
    return readings[-1][1]


@pytest.mark.parametrize("width, height", [(1920, 1080), (2560, 1440)])
def test_offered_scales_are_the_ones_hyprland_runs(bench, page, width, height):
    for scale in (1.25, 1.5, 1.75, 2):
        bench.eval(f'hl.monitor({{ output = "{OUTPUT}", mode = "{width}x{height}@60", position = "0x0", scale = {scale} }})')
        ran = settled_scale(bench, width)
        offered = float(page.call("displayPageProbe", "cleanScale", str(width), str(height), str(scale)))
        assert abs(offered - ran) < 1e-6, f"{width}x{height} at {scale}: offered {offered}, Hyprland runs {ran}"
