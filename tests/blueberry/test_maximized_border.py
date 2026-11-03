"""A maximised window is not resized by its border.

On Windows a maximised window fills its place until it is put back, and its
edges cannot be pulled. Here Hyprland resized one like any floating window when
its lower border was taken hold of, and it stayed tagged as maximised at the
new size. The minimize plugin refuses to begin a resize of a window tagged
maximized, at the drag controller, where a resize from a mouse bind or at the
application's request begins as well.
"""

import time

from blueberry.test_maximize import area, is_maximized
from blueberry.test_placement_gap import set_style


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


def test_a_press_by_a_maximized_windows_border_is_not_swallowed(bench, desk):
    # Refused once it had begun, the resize took the press with it, and the
    # strip round a maximised window, between it and the edges with a
    # floating dock, took no clicks at all.
    bench.eval('hl.config({ general = { resize_on_border = true } })')
    set_style(desk, "floating")
    try:
        x, y, w, h = area(desk)
        under = desk.wayland(width=w, height=h)
        time.sleep(0.5)
        bench.eval(f'hl.dispatch(hl.dsp.window.move({{ window = "address:{under.address}", x = {x}, y = {y} }}))')
        window = desk.wayland()
        desk.place(window, "maximized")
        top = window.wait(lambda c: "maximized" in c["tags"] and c["at"][0] > x, "maximised a gap off the edges")
        under.command("clicks")
        window.command("clicks")
        tx, ty = top["at"]
        _, th = top["size"]
        pointer = desk.pointer()
        pointer.move(tx + 30, ty + th // 2)
        pointer.click(tx - 3, ty + th // 2)
        time.sleep(0.4)
        reached = under.command("clicks")["clicks"] + window.command("clicks")["clicks"]
        assert reached > 0, "the press by the border reached nothing"
    finally:
        set_style(desk, "attached")
