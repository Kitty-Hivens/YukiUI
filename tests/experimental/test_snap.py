"""Snapping a window to a half or a quarter of its screen, by the shell and with the mouse."""

import time

from experimental.test_maximize import area, is_maximized, without_decorations


def zone_rect(desk, zone):
    x, y, w, h = area(desk)
    hw, hh = round(w / 2), round(h / 2)
    return {
        "left": (x, y, hw, h),
        "right": (x + hw, y, w - hw, h),
        "topleft": (x, y, hw, hh),
        "bottomright": (x + hw, y + hh, w - hw, h - hh),
    }[zone]


def test_snapped_window_is_square(desk):
    window = desk.wayland()
    for zone in ("left", "right", "topleft", "bottomright"):
        desk.place(window, zone)
        rect = zone_rect(desk, zone)
        window.wait(lambda c, rect=rect: (*c["at"], *c["size"]) == rect and c["tags"] == ["snapped"], f"snapped {zone}")
        window.wait_state(without_decorations, f"it draws no decorations in {zone}")


def test_restoring_a_snapped_window_puts_it_back(desk):
    window = desk.wayland()
    before = window.rect
    desk.place(window, "left")
    window.wait(lambda c: c["tags"] == ["snapped"], "snapped")
    desk.restore(window)
    client = window.wait(lambda c: not c["tags"], "put back")
    assert (*client["at"], *client["size"]) == before
    window.wait_state(without_decorations, "it still draws no decorations")


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


def test_restoring_a_window_snapped_by_dragging_puts_it_where_it_stood(desk):
    # Where it stood before the drag, not where it was let go of at the edge,
    # half off the screen.
    window = desk.wayland()
    before = window.rect
    pointer = drag_by_title(desk, window, 0, 500)
    pointer.release()
    window.wait(lambda c: (*c["at"], *c["size"]) == zone_rect(desk, "left"), "snapped left by the drag")
    desk.restore(window)
    client = window.wait(lambda c: not c["tags"], "put back")
    assert (*client["at"], *client["size"]) == before


def test_a_snapped_window_dragged_to_another_edge_still_goes_back_where_it_stood(desk):
    window = desk.wayland()
    before = window.rect
    desk.place(window, "left")
    window.wait(lambda c: c["tags"] == ["snapped"], "snapped left")
    pointer = drag_by_title(desk, window, 1919, 500)
    pointer.release()
    window.wait(lambda c: (*c["at"], *c["size"]) == zone_rect(desk, "right"), "snapped right by the drag")
    desk.restore(window)
    client = window.wait(lambda c: not c["tags"], "put back")
    assert (*client["at"], *client["size"]) == before


def test_a_snapped_window_flicked_away_gets_its_own_size(desk):
    # Its size comes back through the plugin while the drag is on, and a drag
    # over at once ended before it came: the window kept the size of its half.
    # Caught about one flick in six before, so several are made.
    for _ in range(6):
        window = desk.wayland()
        _, _, width, height = window.rect
        desk.place(window, "left")
        window.wait(lambda c: c["tags"] == ["snapped"], "snapped")
        x, y, w, _ = window.rect
        pointer = desk.pointer()
        pointer.move(x + w // 2, y + TITLE)
        pointer.press()
        time.sleep(0.03)
        pointer.glide(x + w // 2 + 300, y + TITLE + 200, step=60, pause=0.002)
        pointer.release()
        window.wait(lambda c: tuple(c["size"]) == (width, height) and not c["tags"], "its own size, no longer snapped")
        window.close()
