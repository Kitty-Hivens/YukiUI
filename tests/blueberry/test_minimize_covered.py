"""A window minimised from under others flies off under them.

Its picture is drawn on an overlay above every window, and a window lying
under another came forward over it the moment it was minimised, then flew
into the dock over everything. The animator is now told, for each window, the
windows standing over it that stay where they are, and leaves their places
out of that window's flight.

Which windows stand over which is read off the compositor's window list:
Hyprland keeps it in the order windows are drawn, and raising one moves it to
the end. The first tests check that with an animator that only writes down
what it is handed. The last one looks, on the card, since leaving a place out
is a mask the software scene graph does not draw.
"""

import json
import subprocess
import time

import pytest
from PIL import Image, ImageChops

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchMinimizeCoveredProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/blueberry/test_minimize_covered.py for a test run, and removed after it.
ShellRoot {
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }
    QtObject {
        id: recorder
        property var seen: []
        function minimize(windows, go) {
            recorder.seen = windows.map(win => ({ address: win.address, coveredBy: win.coveredBy }));
            go();
        }
        function restore(windows, go) {
            go();
        }
    }
    Binding {
        target: Minimize
        property: "animator"
        value: recorder
    }
    IpcHandler {
        target: "coveredProbe"
        function ready(): string {
            return HyprlandData.windowList ? "yes" : "";
        }
        function seen(): string {
            return JSON.stringify(recorder.seen);
        }
        function forget(): void {
            recorder.seen = [];
        }
    }
}
"""


@pytest.fixture
def recorded(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("coveredProbe", "ready"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def put(bench, window, x: int, y: int, w: int, h: int):
    target = f'window = "address:{window.address}"'
    bench.eval(f'hl.dispatch(hl.dsp.window.resize({{ {target}, x = {w}, y = {h} }})) '
               f'hl.dispatch(hl.dsp.window.move({{ {target}, x = {x}, y = {y} }}))')
    window.wait(lambda c: c["at"] == [x, y] and c["size"] == [w, h], f"at {x},{y} sized {w}x{h}")


def raise_(bench, window):
    bench.eval(f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{window.address}" }}))')


def rect(window) -> dict:
    client = window.client()
    return {"x": client["at"][0], "y": client["at"][1], "w": client["size"][0], "h": client["size"][1]}


def minimized_with(shell, window) -> list:
    """Minimises a window and returns what the animator was handed for it."""
    shell.call("coveredProbe", "forget")
    shell.call("minimize", "toggle", window.address)
    window.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised")
    seen = json.loads(wait_until(lambda: (text := shell.call("coveredProbe", "seen")) != "[]" and text,
                                 what="the animator to be handed the window"))
    return seen


def restored(shell, window, workspace: int):
    shell.call("minimize", "toggle", window.address)
    window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")


@pytest.fixture
def stacked(bench, desk):
    """Two floating windows, `lower` partly under `upper`."""
    lower = desk.wayland("lower")
    upper = desk.wayland("upper")
    for window in (lower, upper):
        assert window.client()["floating"], "the windows of this desktop float"
    put(bench, lower, 200, 150, 900, 500)
    put(bench, upper, 600, 400, 900, 500)
    raise_(bench, upper)
    return lower, upper


def test_a_window_under_another_is_told_what_covers_it(bench, stacked, recorded):
    lower, upper = stacked
    workspace = lower.client()["workspace"]["id"]
    assert minimized_with(recorded, lower) == [{"address": lower.address, "coveredBy": [rect(upper)]}]

    # Back, it comes up in front, and now the other one lies under it.
    restored(recorded, lower, workspace)
    assert minimized_with(recorded, upper) == [{"address": upper.address, "coveredBy": [rect(lower)]}]
    restored(recorded, upper, workspace)


def test_a_window_in_front_is_covered_by_nothing(bench, stacked, recorded):
    lower, upper = stacked
    workspace = upper.client()["workspace"]["id"]
    assert minimized_with(recorded, upper) == [{"address": upper.address, "coveredBy": []}]
    restored(recorded, upper, workspace)


def test_windows_going_together_do_not_cover_each_other(bench, stacked, recorded):
    lower, upper = stacked
    workspace = lower.client()["workspace"]["id"]
    recorded.call("coveredProbe", "forget")
    recorded.call("minimize", "desktop")
    for window in (lower, upper):
        window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    seen = json.loads(wait_until(lambda: (text := recorded.call("coveredProbe", "seen")) != "[]" and text,
                                 what="the animator to be handed the windows"))
    # From the bottom up, the order their pictures are drawn in.
    assert seen == [{"address": lower.address, "coveredBy": []}, {"address": upper.address, "coveredBy": []}]
    recorded.call("minimize", "desktop")
    for window in (lower, upper):
        window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")


ANIMATED = SHELL / "benchMinimizeCoveredAnimationProbe.qml"
ANIMATED_SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.blueberry.dock
import qs.blueberry.minimize

// Written by tests/blueberry/test_minimize_covered.py for a test run, and removed after it.
ShellRoot {
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }
    ExMinimizeAnimator {
        id: animator
        // Slowed down, for a picture to be taken on the way.
        duration: 4000
    }
    Binding {
        target: Minimize
        property: "animator"
        value: animator
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.blueberry.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.blueberry.dock.edge = "bottom";
    }
    ExDock {}
    IpcHandler {
        target: "coveredAnimationProbe"
        function ready(): bool {
            return Config.ready;
        }
        function flights(): int {
            return animator.flights.length;
        }
    }
}
"""


@pytest.fixture
def animated(bench):
    bench.forget_notifications()
    shell = Shell(bench, probe=ANIMATED, source=ANIMATED_SOURCE, ready=("coveredAnimationProbe", "ready"), gpu=True)
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def screenshot(bench, path):
    subprocess.run(["grim", "-o", OUTPUT, str(path)], env=bench.environment(), check=True)
    return Image.open(path).convert("RGB")


def test_the_window_over_it_stays_in_sight_over_its_picture(bench, stacked, animated, tmp_path):
    lower, upper = stacked
    workspace = lower.client()["workspace"]["id"]
    # The dock has its buttons by now, to fly into.
    time.sleep(1.5)
    # Inside the upper window, clear of its rounded corners and its edge.
    box = (600 + 24, 400 + 24, 600 + 900 - 24, 400 + 500 - 24)
    before = screenshot(bench, tmp_path / "before.png").crop(box)

    animated.call("minimize", "toggle", lower.address)
    lower.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    # A quarter of the way, the picture is still mostly where the window stood.
    time.sleep(1.0)
    assert animated.call("coveredAnimationProbe", "flights") == "1", "the picture is in the air"
    during = screenshot(bench, tmp_path / "during.png")
    difference = ImageChops.difference(before, during.crop(box)).getbbox()
    assert difference is None, f"the picture showed over the window covering it, within {difference} of it"

    wait_until(lambda: animated.call("coveredAnimationProbe", "flights") == "0", timeout=8, what="the flight to end")
    restored(animated, lower, workspace)
    wait_until(lambda: animated.call("coveredAnimationProbe", "flights") == "0", timeout=8, what="the flight back to end")
