"""The resize cursor shows only on the sides of a window that pulling moves.

Hyprland showed it on every side of every window, judged by its shape alone.
A tiled window does not move on a side against the edge of the screen, only
on one it shares with a neighbour, and a window an environment holds at its
size, by the tag it names to the plugins, does not move at all. The
border-resize plugin leaves those sides out, and says through
hl.plugin.border_resize.cursor() what the cursor is overridden with, which is
read here rather than off a picture.
"""

import time

import pytest

# Just outside a side, in the grab area round the window.
OUTSIDE = 3
# How far a neighbour can stand and still share a side, as the plugin reckons it.
REACH = 48


def rect(window) -> tuple:
    client = window.client()
    return (*client["at"], *client["size"])


def cursor(bench) -> str:
    return bench.lua_value("hl.plugin.border_resize.cursor()")


def hover(desk, pointer, x: int, y: int, inside: tuple):
    """Comes to a point from inside the window, as a hand coming to its edge does."""
    pointer.move(*inside)
    time.sleep(0.15)
    pointer.move(x, y)
    time.sleep(0.25)


def side_points(box: tuple) -> dict:
    x, y, w, h = box
    return {
        "left": ((x - OUTSIDE, y + h // 2), (x + 30, y + h // 2)),
        "right": ((x + w + OUTSIDE, y + h // 2), (x + w - 30, y + h // 2)),
        "top": ((x + w // 2, y - OUTSIDE), (x + w // 2, y + 30)),
        "bottom": ((x + w // 2, y + h + OUTSIDE), (x + w // 2, y + h - 30)),
    }


def has_neighbour(box: tuple, side: str, others: list) -> bool:
    x, y, w, h = box
    for ox, oy, ow, oh in others:
        beside_y = oy < y + h and oy + oh > y
        beside_x = ox < x + w and ox + ow > x
        if side == "right" and beside_y and 0 <= ox - (x + w) <= REACH:
            return True
        if side == "left" and beside_y and 0 <= x - (ox + ow) <= REACH:
            return True
        if side == "bottom" and beside_x and 0 <= oy - (y + h) <= REACH:
            return True
        if side == "top" and beside_x and 0 <= y - (oy + oh) <= REACH:
            return True
    return False


@pytest.fixture
def borders(bench):
    bench.eval('hl.config({ general = { resize_on_border = true } })')
    assert "border-resize" in bench.hyprctl("plugin", "list")


def test_tiled_windows_show_it_only_towards_a_neighbour(bench, desk, borders):
    bench.eval('hl.window_rule({ match = { class = "^(bench\\\\.tiled.*)$" }, float = false, tile = true })')
    # Five, so the layout cuts the screen unevenly: sides shared with one
    # neighbour, with two, and against the screen's edge.
    windows = []
    for _ in range(5):
        windows.append(desk.wayland(stem="tiled"))
        time.sleep(0.5)
    time.sleep(0.8)
    boxes = [rect(window) for window in windows]
    pointer = desk.pointer()
    wrong = []
    for index, box in enumerate(boxes):
        others = boxes[:index] + boxes[index + 1:]
        for side, (point, inside) in side_points(box).items():
            hover(desk, pointer, *point, inside)
            shown = cursor(bench)
            if bool(shown) != has_neighbour(box, side, others):
                wrong.append(f"window {index} {box} {side}: {shown or 'no resize cursor'}")
    assert not wrong, "\n".join(wrong)


def test_tiled_window_moves_only_on_a_side_it_shares(bench, desk, borders):
    # What the cursor follows, checked rather than assumed: pulled by a side
    # against the screen's edge a tiled window stays as it is.
    bench.eval('hl.window_rule({ match = { class = "^(bench\\\\.tiled.*)$" }, float = false, tile = true })')
    left = desk.wayland(stem="tiled")
    time.sleep(0.5)
    desk.wayland(stem="tiled")
    time.sleep(0.8)
    pointer = desk.pointer()
    for side, moves in (("left", False), ("right", True)):
        before = rect(left)
        (x, y), inside = side_points(before)[side]
        hover(desk, pointer, x, y, inside)
        pointer.press()
        pointer.glide(x + (60 if side == "left" else -60), y)
        pointer.release()
        time.sleep(0.5)
        assert (rect(left) != before) == moves, f"pulled by its {side} side: {before} -> {rect(left)}"


def held(bench, desk, named: bool):
    """A floating window tagged held, the tag named to the plugin or not."""
    if named:
        bench.eval('hl.config({ plugin = { border_resize = { fixed_size_tag = "held" } } })')
    window = desk.wayland()
    time.sleep(0.5)
    bench.eval(f'hl.dispatch(hl.dsp.window.tag({{ tag = "+held", window = "address:{window.address}" }}))')
    return window


def test_a_window_held_at_its_size_shows_it_nowhere(bench, desk, borders):
    window = held(bench, desk, named=True)
    pointer = desk.pointer()
    shown = []
    for side, (point, inside) in side_points(rect(window)).items():
        hover(desk, pointer, *point, inside)
        if cursor(bench):
            shown.append(side)
    assert not shown, f"a resize cursor on {shown}"


def test_a_tag_no_environment_named_holds_nothing(bench, desk, borders):
    # The bench loads the experimental environment's rules, which name
    # maximized; held is named by nobody here.
    window = held(bench, desk, named=False)
    pointer = desk.pointer()
    (x, y), inside = side_points(rect(window))["left"]
    hover(desk, pointer, x, y, inside)
    assert cursor(bench).endswith("_side")


def test_a_floating_window_shows_it_on_every_side(bench, desk, borders):
    window = desk.wayland()
    time.sleep(0.5)
    pointer = desk.pointer()
    wrong = []
    for side, (point, inside) in side_points(rect(window)).items():
        hover(desk, pointer, *point, inside)
        if not cursor(bench).endswith("_side"):
            wrong.append(side)
    assert not wrong, f"no resize cursor on {wrong}"
