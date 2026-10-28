"""The room left round placed windows, which follows the dock's style.

Against an attached dock a maximised window meets the edges of the work area
and a snapped one its neighbour, drawn square, as on Windows. With the dock
standing off the edge, floating or as an island, they stand off the edges and
each other by as much and keep their round corners, border and shadow: they
met the top of a floating dock with nothing between, while the dock stood off
the screen's edge below it.
"""

import pytest

from bench.bench import wait_until
from experimental.test_maximize import SNAPPED, area

# The dock's floating gap, ExLooks.dock.floatingGap.
GAP = 8


def set_style(desk, style: str):
    wait_until(lambda: desk.shell.call("benchConfig", "setDockStyle", style) == style, what=f"the dock style to be {style}")


@pytest.fixture
def floating(desk):
    set_style(desk, "floating")
    try:
        yield
    finally:
        set_style(desk, "attached")


def rect(client) -> tuple:
    return (*client["at"], *client["size"])


def test_against_an_attached_dock_placed_windows_are_square(desk):
    maximized = desk.wayland()
    snapped = desk.wayland()
    desk.place(maximized, "maximized")
    desk.place(snapped, "left")
    maximized.wait(lambda c: rect(c) == area(desk) and set(c["tags"]) == {"maximized", "square", "bare"}, "maximised, square and bare")
    snapped.wait(lambda c: set(c["tags"]) == SNAPPED, "snapped and square")


def test_with_a_floating_dock_placed_windows_stand_off_the_edges(desk, floating):
    x, y, w, h = area(desk)
    inner = (x + GAP, y + GAP, w - 2 * GAP, h - 2 * GAP)
    half = round((inner[2] - GAP) / 2)
    maximized = desk.wayland()
    left = desk.wayland()
    right = desk.wayland()
    desk.place(maximized, "maximized")
    desk.place(left, "left")
    desk.place(right, "right")
    maximized.wait(lambda c: rect(c) == inner and c["tags"] == ["maximized"], "maximised a gap off the edges, drawn as any window")
    left.wait(lambda c: rect(c) == (inner[0], inner[1], half, inner[3]) and c["tags"] == ["snapped"], "snapped left, a gap off the edges")
    far = inner[0] + half + GAP
    right.wait(lambda c: rect(c) == (far, inner[1], inner[0] + inner[2] - far, inner[3]), "snapped right, a gap off its neighbour")


def test_changing_the_dock_style_refits_placed_windows(desk):
    window = desk.wayland()
    desk.place(window, "maximized")
    window.wait(lambda c: rect(c) == area(desk) and "bare" in c["tags"], "maximised against the edges")
    x, y, w, h = area(desk)
    set_style(desk, "floating")
    try:
        window.wait(lambda c: rect(c) == (x + GAP, y + GAP, w - 2 * GAP, h - 2 * GAP) and c["tags"] == ["maximized"],
                    "fitted a gap off the edges", timeout=5)
    finally:
        set_style(desk, "attached")
    window.wait(lambda c: rect(c) == area(desk) and "bare" in c["tags"], "against the edges again", timeout=5)
