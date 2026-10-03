"""Flyouts of a dock at the side of the screen, as their content grows.

A popup window changes size only once the compositor has answered, and beside
a side dock the window was centred on its button, so it was resized on every
frame of a panel growing, and grew both ways. The panel now grows one way,
away from the edge that stands still, in a window that keeps its size.

The notification center opens from the clock, at the far end of a dock on the
left, so it grows upwards and its bottom edge must not move. The desktop is
plain red so the panel is easy to find in a capture.
"""

import subprocess
import time

import pytest
from PIL import Image

from bench.bench import HEIGHT, OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockFlyoutProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.experimental
import qs.experimental.dock

// Written by tests/experimental/test_dock_flyouts.py for a test run, and removed after it.
ShellRoot {
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.experimental.dock.edge = "left";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.experimental.dock.edge = "left";
    }
    ExDock {}

    // How many times the open flyout's window was asked for a new size.
    property int resizes: 0
    Connections {
        target: ExStates.openPopup
        function onImplicitHeightChanged() {
            probe.resizes += 1;
        }
    }
    id: probe
    IpcHandler {
        target: "flyoutProbe"
        function resizes(): int {
            return probe.resizes;
        }
        function reset(): void {
            probe.resizes = 0;
        }
    }
}
"""

# Where the panel is looked for, across the screen: right of the dock.
COLUMN = 260


@pytest.fixture
def left_dock(bench):
    bench.eval('hl.config({ misc = { force_default_wallpaper = 0, background_color = "rgb(ff0000)" } })')
    # Kept by an earlier test's shell, they would be loaded as this one's.
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dock", "activate", "99"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval('hl.config({ misc = { force_default_wallpaper = -1, background_color = "rgb(111111)" } })')


def plane_edges(path) -> tuple[int, int] | None:
    """The top and the bottom of the panel in a capture: the first and last
    rows down the column that are not the red desktop."""
    image = Image.open(path).convert("RGB")
    rows = [y for y in range(HEIGHT) if (lambda p: not (p[0] > 200 and p[1] < 60 and p[2] < 60))(image.getpixel((COLUMN, y)))]
    return (rows[0], rows[-1]) if rows else None


def notify(shell, summary):
    subprocess.run(["notify-send", "-t", "600000", summary, "A body long enough to give the card a second line of text"],
                   env=shell.environment(), check=True)


def test_center_beside_a_left_dock_grows_up_from_a_still_bottom(left_dock, bench, tmp_path):
    shell = left_dock
    notify(shell, "First")
    time.sleep(0.5)
    shell.call("dock", "notifications")
    time.sleep(1.2)
    frames = []
    shell.call("flyoutProbe", "reset")
    notify(shell, "Second")
    deadline = time.monotonic() + 1.2
    while time.monotonic() < deadline:
        shot = tmp_path / f"frame-{len(frames):03d}.png"
        subprocess.run(["grim", "-o", OUTPUT, str(shot)], env=bench.environment(), check=True)
        edges = plane_edges(shot)
        if edges:
            frames.append(edges)
    assert len(frames) > 5, frames
    tops = [top for top, _ in frames]
    bottoms = [bottom for _, bottom in frames]
    assert max(bottoms) - min(bottoms) <= 1, f"the bottom moved: {bottoms}"
    assert tops[-1] < tops[0], f"it did not grow upwards: {tops}"
    # Room taken once as it grows, and cut down once after: resized on
    # every frame, nothing was drawn while the compositor answered.
    assert int(shell.call("flyoutProbe", "resizes")) <= 2
