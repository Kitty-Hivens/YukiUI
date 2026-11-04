"""A wallpaper made under a fullscreen window shows once that window is gone.

Hyprland 0.57 gives a layer mapped under a fullscreen window no fade in, and
nothing later raises one below the top layer. A shell restarted during a game
came back with no wallpaper at all, the compositor's own colour in its place.
"""

import subprocess
import time

import pytest
from PIL import Image

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchBackgroundProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.background

// Written by tests/blueberry/test_background_after_fullscreen.py for a test run, and removed after it.
ShellRoot {
    ExBackground {}
    IpcHandler {
        target: "backgroundProbe"
        function ready(): bool {
            return true;
        }
    }
}
"""


def corner(bench, tmp_path) -> tuple:
    shot = tmp_path / "corner.png"
    subprocess.run(["grim", "-o", OUTPUT, str(shot)], env=bench.environment(), check=True)
    return Image.open(shot).convert("RGB").getpixel((20, 20))


def test_the_wallpaper_shows_after_the_fullscreen_it_was_made_under(bench, desk, tmp_path):
    window = desk.wayland()
    window.command("fullscreen")
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen")
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("backgroundProbe", "ready"))
    shell.start()
    try:
        time.sleep(2.0)
        window.command("unfullscreen")
        window.wait(lambda c: c["fullscreen"] == 0, "back from fullscreen")
        # The window of the wallpaper is filled black, and the bench has no
        # picture for it: the compositor's own colour is grey.
        wait_until(lambda: corner(bench, tmp_path) == (0, 0, 0), timeout=8, what="the wallpaper's window to show")
    finally:
        shell.stop()
        shell.remove_probe()
