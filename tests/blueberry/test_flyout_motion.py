"""How the dock's panels come and go, followed frame by frame.

A panel used to be cut off at the dock's edge on its way in and out, as if it
came from behind the dock. Through a dock that lets the screen show, that read
as a panel sliced along a ruler, and past the dock's rounded corner the slice
stood over bare desktop. Leaving, it set off so slowly that it stood nearly
still for the first ninety milliseconds after the click.

Now a panel in a corner of the screen comes in from the screen's edge, which
hides it on the way, and goes back out through it, as Waffle's notification
center does. One away from a corner rises from the dock and leaves towards it,
at once. Nothing of either may pass the window's edge on the dock's side, which
is where the window would cut it.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchFlyoutMotionProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_flyout_motion.py for a test run, and removed after it.
ShellRoot {
    id: probe

    function place() {
        Config.options.blueberry.dock.edge = "EDGE";
        Config.options.blueberry.dock.style = "STYLE";
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                probe.place();
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            probe.place();
    }
    ExDock {}

    // The popup last opened, kept while it closes.
    property var popup: null
    Connections {
        target: ExStates
        function onOpenPopupChanged() {
            if (ExStates.openPopup)
                probe.popup = ExStates.openPopup;
        }
    }

    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }

    property bool recording: false
    property var frames: []
    property real since: 0
    function sample() {
        const surface = probe.find(probe.popup?.contentItem, item => item.entryTravel !== undefined);
        if (!surface || !surface.visible)
            return;
        const at = surface.mapToItem(probe.popup.contentItem, 0, 0);
        probe.frames.push({
            t: Date.now() - probe.since,
            x: at.x,
            y: at.y,
            w: surface.width,
            h: surface.height,
            opacity: surface.opacity,
            windowWidth: probe.popup.width,
            windowHeight: probe.popup.height
        });
    }
    FrameAnimation {
        running: probe.recording
        onTriggered: probe.sample()
    }
    // Time is counted from the click, not from the call that started the
    // recording, which the call after it takes a while to follow.
    Connections {
        target: probe.popup
        function onOpenChanged() {
            probe.since = Date.now();
        }
    }

    IpcHandler {
        target: "flyoutMotion"
        function record(): void {
            probe.frames = [];
            probe.since = Date.now();
            probe.recording = true;
        }
        function frames(): string {
            probe.recording = false;
            return JSON.stringify(probe.frames);
        }
        function entry(): string {
            return probe.popup?.entry ?? "none";
        }
        function shown(): bool {
            return probe.popup?.visible ?? false;
        }
    }
}
"""

# The gap between the dock and a panel at rest, as far as a panel may move
# towards the dock.
GAP = 8


def dock_shell(bench, edge, style):
    source = SOURCE.replace("EDGE", edge).replace("STYLE", style)
    return Shell(bench, probe=PROBE, source=source, ready=("dock", "activate", "99"), own_bus=True)


@pytest.fixture
def run_shell(bench):
    shells = []

    def start(edge, style):
        shell = dock_shell(bench, edge, style)
        shells.append(shell)
        shell.start()
        return shell

    try:
        yield start
    finally:
        for shell in shells:
            shell.stop()
            shell.remove_probe()


def follow(shell, flyout):
    shell.call("flyoutMotion", "record")
    shell.call("dock", flyout)
    time.sleep(1.0)
    frames = json.loads(shell.call("flyoutMotion", "frames"))
    assert len(frames) >= 5, frames
    return frames


def within_dock_side(frames, edge):
    """Every frame is clear of the window's edge on the dock's side."""
    for f in frames:
        if edge == "bottom":
            assert f["y"] + f["h"] <= f["windowHeight"] + 0.5, f
        elif edge == "left":
            assert f["x"] >= -0.5, f


def leaves_towards_the_dock_at_once(frames, rest, edge):
    along, across = ("x", "y") if edge == "bottom" else ("y", "x")
    sign = 1 if edge == "bottom" else -1
    assert all(abs(f[along] - rest[along]) < 0.5 for f in frames), "it moved along the dock while leaving"
    gone = [sign * (f[across] - rest[across]) for f in frames]
    assert max(gone) <= GAP + 0.5, f"it went {max(gone)} towards the dock"
    assert gone == sorted(gone), f"it did not keep going towards the dock: {gone}"
    # Set off at speed: a quarter of the way within forty milliseconds of the
    # click. The ease it had did not get a tenth of the way in ninety.
    early = next((f for f in frames if f["t"] >= 40), None)
    assert early is not None, frames
    moved = sign * (early[across] - rest[across])
    assert moved >= GAP / 4, f"{moved} of {GAP} after {early['t']} ms"
    assert early["opacity"] < 1, "it had not begun to fade"


def goes_back_out(frames, rest, entry):
    """Leaves the way it came, whole, until it is past the screen's edge."""
    along, across, sign = {"right": ("x", "y", 1), "bottom": ("y", "x", 1)}[entry]
    assert all(abs(f[across] - rest[across]) < 0.5 for f in frames), "it moved across the dock while leaving"
    assert all(f["opacity"] == 1 for f in frames), "it faded instead of leaving whole"
    out = [sign * (f[along] - rest[along]) for f in frames]
    assert out == sorted(out), f"it did not keep going out: {out}"
    # The last frame drawn: the run ends fast, and the frame after it is past the edge.
    assert out[-1] >= rest["w" if along == "x" else "h"] / 2, f"it was last drawn only {out[-1]} out"


def test_a_corner_panel_comes_in_from_the_screen_edge(run_shell):
    shell = run_shell("bottom", "attached")
    opening = follow(shell, "notifications")
    assert shell.call("flyoutMotion", "entry") == "right"
    rest = opening[-1]
    assert opening[0]["x"] > rest["x"] + rest["w"] / 2, f"it did not come from the right: {opening[0]} then {rest}"
    xs = [f["x"] for f in opening]
    assert xs == sorted(xs, reverse=True), f"it did not keep coming in: {xs}"
    assert all(abs(f["y"] - rest["y"]) < 0.5 for f in opening), "it moved across the dock while coming in"
    # Coming in from out of sight, it is whole all the way.
    assert all(f["opacity"] == 1 for f in opening)
    within_dock_side(opening, "bottom")

    closing = follow(shell, "notifications")
    within_dock_side(closing, "bottom")
    goes_back_out(closing, rest, "right")
    # Held up a moment past the end, until empty frames have reached the
    # compositor, and then let go of.
    wait_until(lambda: shell.call("flyoutMotion", "shown") == "false", timeout=2, what="the popup window to go")
    assert not shell.errors()


def test_a_panel_away_from_a_corner_rises_from_the_dock(run_shell):
    # On an island the clock's end is well off the screen edge.
    shell = run_shell("bottom", "island")
    opening = follow(shell, "notifications")
    assert shell.call("flyoutMotion", "entry") == ""
    rest = opening[-1]
    assert all(abs(f["x"] - rest["x"]) < 0.5 for f in opening), "it moved along the dock"
    assert opening[0]["y"] > rest["y"], "it did not rise from the dock"
    assert opening[0]["y"] - rest["y"] <= GAP + 0.5
    within_dock_side(opening, "bottom")

    closing = follow(shell, "notifications")
    within_dock_side(closing, "bottom")
    leaves_towards_the_dock_at_once(closing, rest, "bottom")
    assert not shell.errors()


def test_beside_a_side_dock_it_comes_in_from_the_bottom(run_shell):
    shell = run_shell("left", "attached")
    opening = follow(shell, "notifications")
    assert shell.call("flyoutMotion", "entry") == "bottom"
    rest = opening[-1]
    assert opening[0]["y"] > rest["y"] + rest["h"] / 2, "it did not come from the bottom"
    assert all(abs(f["x"] - rest["x"]) < 0.5 for f in opening), "it moved across the dock while coming in"
    within_dock_side(opening, "left")

    closing = follow(shell, "notifications")
    within_dock_side(closing, "left")
    goes_back_out(closing, rest, "bottom")
    assert not shell.errors()

