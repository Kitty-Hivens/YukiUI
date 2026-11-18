"""The pen-lock plugin: an absolute pointing device moves a game holding the
pointer locked.

A game under Wine on Wayland locks the pointer while fullscreen and takes
relative motion only. A pen tablet moves the pointer to a place, which
Hyprland undoes at once under a lock and tells the game nothing of: the pen
did nothing in the game. The plugin tells the game the way from the pen's
place before. The bench's pointer moves to places as a pen does.
"""

import re
import time

from bench.bench import wait_until
from core.test_border_resize import Locked


def moved(game) -> tuple[float, float]:
    total_x = total_y = 0.0
    for line in game.heard():
        found = re.fullmatch(r"relative (-?[\d.]+) (-?[\d.]+)", line)
        if found:
            total_x += float(found.group(1))
            total_y += float(found.group(2))
    return round(total_x, 2), round(total_y, 2)


def test_a_place_reaches_a_locked_game_as_the_way_there(bench, desk):
    assert "pen-lock" in bench.hyprctl("plugin", "list")
    pointer = desk.pointer()
    pointer.move(600, 400)
    game = Locked(bench)
    try:
        wait_until(lambda: "ready" in game.heard(), timeout=10, what="the game shown")
        # The lock takes once the pointer is over the game.
        pointer.move(610, 400)
        wait_until(lambda: "locked" in game.heard(), timeout=10, what="the game to hold the pointer")
        time.sleep(0.2)
        before = moved(game)

        pointer.move(710, 450)
        pointer.move(760, 430)
        wait_until(lambda: moved(game) == (before[0] + 150, before[1] + 30),
                   what="the way from 610,400 to 760,430 told to the game")
        # And back, so it goes both ways.
        pointer.move(610, 400)
        wait_until(lambda: moved(game) == before, what="the way back told to the game")
        assert "unlocked" not in game.heard(), f"the game lost the pointer: {game.heard()}"
    finally:
        game.close()
