"""A maximised window is not resized by its border.

On Windows a maximised window fills its place until it is put back, and its
edges cannot be pulled. Here Hyprland resized one like any floating window when
its lower border was taken hold of, and it stayed tagged as maximised at the
new size. The minimize plugin refuses to begin a resize of a window tagged
maximized, at the drag controller, where a resize from a mouse bind or at the
application's request begins as well.
"""

import time

from experimental.test_maximize import is_maximized


def test_a_maximized_window_is_not_resized_by_its_border(bench, desk):
    bench.eval('hl.config({ general = { resize_on_border = true } })')
    window = desk.wayland()
    desk.place(window, "maximized")
    client = window.wait(lambda c: is_maximized(desk, c), "maximised")
    before = (*client["at"], *client["size"])
    x, y, w, h = before
    # Just below its lower edge, in the grab area round it, and pulled up.
    sx, sy = x + w // 2, y + h + 3
    pointer = desk.pointer()
    pointer.move(sx, sy + 20)
    pointer.move(sx, sy)
    pointer.press()
    pointer.glide(sx, sy - 200)
    pointer.release()
    time.sleep(0.5)
    client = window.client()
    assert (*client["at"], *client["size"]) == before, "the maximised window was resized by its border"
    assert "maximized" in client["tags"]
