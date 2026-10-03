"""The session menu: lock, sleep, log out, restart, shut down.

Nothing here presses a button or Enter. The actions are the real ones: Logout
ends every Hyprland by name, the person's own included, and Lock locks the
live session. What is checked is which button is picked, read off the screen.

Opened under a pointer standing still at the middle of the screen, where a
window's centre leaves it, hover picked the button lying there, Logout, and
Enter meant to lock logged out.
"""

import subprocess
import time

import pytest
from PIL import Image

from bench.bench import OUTPUT, SHELL, WIDTH, HEIGHT
from bench.shell import Shell
from bench.windows import Pointer

PROBE = SHELL / "benchSessionProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.experimental.session

// Written by tests/experimental/test_session_menu.py for a test run, and removed after it.
ShellRoot {
    ExSession {}
}
"""


@pytest.fixture
def session(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("session", "close"))
    pointer = Pointer(bench)
    try:
        shell.start()
        yield shell, pointer
    finally:
        try:
            shell.call("session", "close")
        finally:
            pointer.close()
            shell.stop()
            shell.remove_probe()


def picked_x(bench, path) -> float:
    """Where the picked button stands across the screen: the middle of the
    strongly coloured pixels in the band the buttons sit in."""
    subprocess.run(["grim", "-o", OUTPUT, str(path)], env=bench.environment(), check=True)
    image = Image.open(path).convert("RGB")
    xs = [x for y in range(HEIGHT // 2 - 80, HEIGHT // 2 + 20, 4) for x in range(0, WIDTH, 2)
          if (lambda p: max(p) - min(p) > 70)(image.getpixel((x, y)))]
    assert xs, "no button was drawn as picked"
    return sum(xs) / len(xs)


def test_still_pointer_does_not_pick_and_a_moved_one_does(session, bench, tmp_path):
    shell, pointer = session
    middle = (WIDTH // 2, HEIGHT // 2 - 13)
    pointer.move(*middle)
    time.sleep(0.2)
    shell.call("session", "open")
    time.sleep(0.8)
    # Lock, the first of five, is picked, well left of the middle.
    assert picked_x(bench, tmp_path / "opened.png") < WIDTH // 2 - 150
    pointer.glide(middle[0] + 20, middle[1])
    time.sleep(0.4)
    # Moved, the pointer picks what it is over, at the middle.
    assert abs(picked_x(bench, tmp_path / "moved.png") - WIDTH // 2) < 60
