"""A dock that hides on its own stays while the pointer is over it, and comes
out over the windows, while one that stays is under them.

The dock watched the pointer from an item laid under it, beside its buttons
rather than around them. Over the clock, whose area takes the hover itself,
the item under it was no longer hovered, and the dock slid away from under the
pointer. A floating dock, as it was seen, with the corner button after the clock.
"""

import json
import subprocess
import time

import pytest
from PIL import Image

from bench.bench import HEIGHT, OUTPUT, SHELL, WIDTH, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockAutoHideProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry.background
import qs.blueberry.dock
import qs.blueberry.looks

// Written by tests/blueberry/test_dock_autohide.py for a test run, and removed after it.
ShellRoot {
    id: probe
    function setUp() {
        Config.options.blueberry.dock.edge = "bottom";
        Config.options.blueberry.dock.style = "floating";
        Config.options.blueberry.dock.showDesktop = true;
        Config.options.blueberry.dock.launcherButton = true;
        Config.options.blueberry.dock.autoHide = true;
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                probe.setUp();
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            probe.setUp();
    }
    ExDock {
        id: dock
    }
    // The wallpaper, which covers the whole screen, so the dock's layer is
    // seen against it.
    ExBackground {}
    IpcHandler {
        target: "autoHideProbe"
        function state(): string {
            const window = dock.docks[0];
            return JSON.stringify({ revealed: window?.revealed ?? false, kept: window?.keepShown ?? false });
        }
        function setAutoHide(on: bool): void {
            Config.options.blueberry.dock.autoHide = on;
        }
    }
}
"""


@pytest.fixture
def dock(bench):
    bench.forget_notifications()
    # The probe sets the dock up in the config file every shell on the bench
    # reads, and the window probe placed windows by a floating dock after it.
    # Put back as it was found.
    config = bench.config_home / "illogical-impulse/config.json"
    before = config.read_bytes() if config.exists() else None
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("autoHideProbe", "state"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        if before is None:
            config.unlink(missing_ok=True)
        else:
            config.write_bytes(before)


def state(shell) -> dict:
    return json.loads(shell.call("autoHideProbe", "state"))


def layer_level(bench, namespace: str) -> str:
    """The layer level a namespace is on: "0" the wallpaper's, "1" under the
    windows, "2" over them, or empty while it is not up yet, so a wait goes on
    rather than ends."""
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for level, layers in data["levels"].items():
            if any(layer["namespace"] == namespace for layer in layers):
                return level
    return ""


def dock_level(bench) -> str:
    return layer_level(bench, "quickshell:dock")


def test_the_dock_is_over_the_windows_hiding_or_not(bench, dock):
    # Hiding on its own, it comes out over the windows, which would cover it.
    wait_until(lambda: dock_level(bench) == "2", what="a hiding dock over the windows")
    # Staying, it is over them as well, as the other environments' bars are:
    # under them, the shadows of the windows fell on it and darkened it.
    dock.call("autoHideProbe", "setAutoHide", "false")
    try:
        wait_until(lambda: dock_level(bench) == "2", what="a dock that stays over the windows")
        # And over the wallpaper, which covers the whole screen: on the same
        # level and made after the dock, it hid the dock completely.
        assert layer_level(bench, "quickshell:background") == "0"
    finally:
        dock.call("autoHideProbe", "setAutoHide", "false")


def dock_layer(bench) -> tuple[int, int, int, int]:
    """Where the dock's layer stands. The bench keeps room at the bottom of
    its screen, and the layer stands above that rather than at the edge."""
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            for layer in layers:
                if layer["namespace"] == "quickshell:dock":
                    return layer["x"], layer["y"], layer["w"], layer["h"]
    raise AssertionError("no dock layer")


def strip_colour(bench, tmp_path, rect) -> tuple:
    """The colour a part of the screen averages to, as it is really shown."""
    shot = tmp_path / "strip.png"
    subprocess.run(["grim", "-o", OUTPUT, str(shot)], env=bench.environment(), check=True)
    x, y, w, h = rect
    return Image.open(shot).convert("RGB").crop((x, y, x + w, y + h)).resize((1, 1)).getpixel((0, 0))


def close_to(a, b) -> bool:
    return all(abs(p - q) <= 6 for p, q in zip(a, b))


def test_the_dock_comes_back_after_a_fullscreen_window(bench, desk, dock, tmp_path):
    # Moved to the layer below by hand as the window took the screen, it stayed
    # there for good, behind every window: the move back takes a commit, and a
    # surface under a fullscreen window draws none. Hidden by the compositor
    # itself it needs no move.
    dock.call("autoHideProbe", "setAutoHide", "false")
    wait_until(lambda: dock_level(bench) == "2", what="the dock over the windows")
    wait_until(lambda: state(dock)["revealed"], what="the dock to be out")
    time.sleep(0.5)
    x, y, w, h = dock_layer(bench)
    rect = (x + 40, y + h - 30, 200, 12)
    window = desk.wayland()
    time.sleep(0.5)
    before = strip_colour(bench, tmp_path, rect)

    window.command("fullscreen")
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen")
    time.sleep(0.8)
    covered = strip_colour(bench, tmp_path, rect)
    assert not close_to(covered, before), f"the dock stayed over the fullscreen window: {covered}"

    window.command("unfullscreen")
    window.wait(lambda c: c["fullscreen"] == 0, "back from fullscreen")
    wait_until(lambda: dock_level(bench) == "2", what="the dock over the windows again")
    wait_until(lambda: close_to(strip_colour(bench, tmp_path, rect), before), what="the dock to show again")


@pytest.mark.parametrize("spot", ["launcher", "clock"])
def test_dock_stays_while_the_pointer_rests_on_it(bench, desk, dock, spot):
    # The pointer starts where the test before left it, over the dock, which
    # rightly keeps it out.
    pointer = desk.pointer()
    pointer.move(WIDTH // 2, HEIGHT // 2)
    wait_until(lambda: not state(dock)["revealed"], timeout=5, what="the dock to hide first")
    x, y, w, h = dock_layer(bench)
    # Down from the middle of the screen to the dock's last row of pixels,
    # which brings it out.
    pointer.glide(x + w // 2, y + h - 1)
    wait_until(lambda: state(dock)["revealed"], timeout=3, what="the dock to come out")
    time.sleep(0.5)
    # Across the plate's middle: the launcher alone in the middle of the
    # dock, the clock just before the corner button at its far end.
    middle = y + h - 8 - 26
    pointer.glide(x + w // 2 if spot == "launcher" else x + w - 40, middle)
    # Whether it means to stay, read every little while. Going to and fro it
    # hid only once a gap in it ran past its delay, which made the hiding
    # itself come and go.
    samples = []
    for _ in range(10):
        time.sleep(0.15)
        samples.append(state(dock))
    assert all(sample["kept"] for sample in samples), f"over the {spot} the dock meant to hide: {samples}"
    assert samples[-1]["revealed"]
