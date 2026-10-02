"""Snapping a window to a half or a quarter of its screen, by the shell and with the mouse."""

import time

from experimental.test_maximize import area, is_maximized, ordinary


def zone_rect(desk, zone):
    x, y, w, h = area(desk)
    hw, hh = round(w / 2), round(h / 2)
    return {
        "left": (x, y, hw, h),
        "right": (x + hw, y, w - hw, h),
        "topleft": (x, y, hw, hh),
        "bottomright": (x + hw, y + hh, w - hw, h - hh),
    }[zone]


def test_snapped_window_is_square_and_tiled(desk):
    window = desk.wayland()
    for zone in ("left", "right", "topleft", "bottomright"):
        desk.place(window, zone)
        rect = zone_rect(desk, zone)
        window.wait(lambda c, rect=rect: (*c["at"], *c["size"]) == rect and c["tags"] == ["snapped"], f"snapped {zone}")
        window.wait_state(ordinary, f"it is tiled and not maximised in {zone}")


def test_restoring_a_snapped_window_puts_it_back(desk):
    window = desk.wayland()
    before = window.rect
    desk.place(window, "left")
    window.wait(lambda c: c["tags"] == ["snapped"], "snapped")
    desk.restore(window)
    client = window.wait(lambda c: not c["tags"], "put back")
    assert (*client["at"], *client["size"]) == before
    window.wait_state(ordinary, "it is an ordinary window again")


# Where the test window is taken hold of: the middle of its title bar. Higher
# up, GTK makes the first fifteen pixels or so a handle for resizing the
# window from its top edge.
TITLE = 30


def drag_by_title(desk, window, to_x, to_y, pointer=None):
    pointer = pointer or desk.pointer()
    x, y, w, _ = window.rect
    pointer.move(x + w // 2, y + TITLE)
    pointer.press()
    time.sleep(0.05)
    pointer.glide(to_x, to_y)
    time.sleep(0.3)
    return pointer


def test_dragging_to_the_left_edge_snaps(desk):
    window = desk.wayland()
    pointer = drag_by_title(desk, window, 0, 500)
    pointer.release()
    window.wait(lambda c: (*c["at"], *c["size"]) == zone_rect(desk, "left"), "snapped left by the drag")


def test_pulling_a_snapped_window_away_gives_its_size_back_under_the_pointer(desk):
    window = desk.wayland()
    _, _, width, height = window.rect
    desk.place(window, "left")
    window.wait(lambda c: c["tags"] == ["snapped"], "snapped")
    pointer = drag_by_title(desk, window, 900, 400)
    client = window.wait(lambda c: tuple(c["size"]) == (width, height), "its own size back")
    x, y = client["at"]
    # Taken by the middle of its title, it is held there still, give or take
    # the steps of the drag.
    assert abs((x + width / 2) - 900) < 40, client
    assert abs((y + TITLE) - 400) < 40, client
    pointer.release()
    window.wait(lambda c: not c["tags"], "no longer snapped")


def test_dragging_to_the_top_maximizes(desk):
    window = desk.wayland()
    pointer = drag_by_title(desk, window, 960, 0)
    pointer.release()
    window.wait(lambda c: is_maximized(desk, c), "maximised by the drag")
