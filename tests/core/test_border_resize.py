"""The border-resize plugin: a window is resized by its border with the left
button only, and never while a game holds the pointer.

Hyprland started a resize on any button pressed round a window, before it asked
whether the focused window held the pointer. A fullscreen game that had locked
the pointer near a picture-in-picture window pinned over it lost its clicks
there to resizing that window, and the focus and its hold on the pointer with
them, and a right click near any window resized it.
"""

import queue
import subprocess
import threading
import time

import pytest

from bench.bench import wait_until
from core.test_pip_rules import pip_rules


class Locked:
    """The bench's game: fullscreen, holding the pointer, saying what reaches it."""

    def __init__(self, bench):
        self.process = subprocess.Popen([str(bench.locked_client), "bench.locked"], env=bench.environment(),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.lines = queue.Queue()
        self.seen = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.strip())

    def heard(self) -> list:
        while True:
            try:
                self.seen.append(self.lines.get_nowait())
            except queue.Empty:
                return self.seen

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()


@pytest.fixture
def pip(bench, desk):
    for rule in pip_rules():
        bench.eval(rule)
    bench.eval('hl.config({ general = { resize_on_border = true } })')
    assert "border-resize" in bench.hyprctl("plugin", "list")
    # Big enough to lie under the grab area round the picture, which stands
    # in the lower right corner.
    under = desk.wayland(width=1800, height=950)
    under.wait(lambda c: desk.active() == c["address"], what="the window under it to have the keyboard")
    picture = desk.wayland(stem="pip", title="Картинка в картинке", width=480, height=270)
    time.sleep(1.0)
    return under, picture


def edge_of(picture) -> tuple[int, int]:
    """Just outside the picture's left side, in the grab area round it."""
    x, y, w, h = picture.rect
    return x - 3, y + h // 2


def test_a_right_press_by_the_border_does_not_resize(bench, desk, pip):
    # Nothing holds the pointer in the grab area round a window, so the press
    # goes nowhere, as a right press on the edge of a window on Windows.
    under, picture = pip
    before = picture.rect
    sx, sy = edge_of(picture)
    pointer = desk.pointer()
    pointer.move(sx + 30, sy)
    pointer.move(sx, sy)
    pointer.press("right")
    pointer.glide(sx - 60, sy)
    pointer.release("right")
    time.sleep(0.4)
    assert picture.rect == before, "a right press by the border resized the window"
    assert desk.active() == under.address, "a right press by the border moved the keyboard"


def test_a_left_press_by_the_border_still_resizes(bench, desk, pip):
    _, picture = pip
    before = picture.rect
    sx, sy = edge_of(picture)
    pointer = desk.pointer()
    pointer.move(sx + 30, sy)
    pointer.move(sx, sy)
    pointer.press()
    pointer.glide(sx - 60, sy)
    pointer.release()
    wait_until(lambda: picture.rect[2] > before[2], what="the window to grow from its border")


def test_a_game_holding_the_pointer_keeps_its_clicks(bench, desk, pip):
    _, picture = pip
    before = picture.rect
    sx, sy = edge_of(picture)
    pointer = desk.pointer()
    # The pointer left by the picture, as it is when the game takes hold of it.
    pointer.move(sx + 30, sy)
    pointer.move(sx, sy)
    game = Locked(bench)
    try:
        wait_until(lambda: "locked" in game.heard(), timeout=10, what="the game to hold the pointer")
        assert picture.rect == before
        pointer.press()
        time.sleep(0.05)
        pointer.release()
        time.sleep(0.5)
        heard = game.heard()
        assert "button 272 pressed" in heard, f"the game's click went elsewhere: {heard}"
        assert "unlocked" not in heard and heard[-1] != "keyboard out", f"the game lost the pointer or the keyboard: {heard}"
        assert picture.rect == before, "the game's click resized the picture"
    finally:
        game.close()
