"""The scales the display page offers are the ones Hyprland runs.

Hyprland runs a scale only when it leaves the screen a whole number of points
across and down, and otherwise picks the nearest one that does, without a
word. The page offered 175% on a 1080p screen, which ran at another scale, and
later offered a fixed list mended to fit, which on 1440p showed 160% and 167%
and left out 133%, the one nearest the 150% that cannot be had there. It now
offers the scales that fit, and this checks each against Hyprland itself.
"""

import json
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
        function cleanScales(width: int, height: int): string {
            return JSON.stringify(page.cleanScales(width, height));
        }
    }
}
"""


@pytest.fixture
def page(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("displayPageProbe", "cleanScales", "1920", "1080"))
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


def offered(page, width, height) -> list[float]:
    return json.loads(page.call("displayPageProbe", "cleanScales", str(width), str(height)))


def near(scales, wanted) -> bool:
    return any(abs(scale - wanted) < 1e-6 for scale in scales)


def test_1440p_offers_133_rather_than_150(page):
    scales = offered(page, 2560, 1440)
    assert near(scales, 4 / 3) and not near(scales, 1.5), scales
    assert near(offered(page, 1920, 1080), 1.5)


@pytest.mark.parametrize("width, height", [(1920, 1080), (2560, 1440)])
def test_offered_scales_are_the_ones_hyprland_runs(bench, page, width, height):
    scales = offered(page, width, height)
    assert scales[0] == 1 and scales[-1] == 2, scales
    for scale in scales:
        bench.eval(f'hl.monitor({{ output = "{OUTPUT}", mode = "{width}x{height}@60", position = "0x0", scale = {scale!r} }})')
        ran = settled_scale(bench, width)
        # Hyprland reports a scale to five places.
        assert abs(scale - ran) < 1e-4, f"{width}x{height}: offered {scale}, Hyprland runs {ran}"
