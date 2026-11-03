"""Where a window comes back when its application opens again.

A Wayland application cannot place its own window, so the compositor rules
remember where the last window of each one stood. An X11 application places
itself, and is left to do so.
"""

from bench.bench import wait_until


def move(desk, window, x, y, w, h):
    target = f'window = "address:{window.address}"'
    desk.bench.eval(f"hl.dispatch(hl.dsp.window.resize({{ {target}, x = {w}, y = {h} }})) "
                    f"hl.dispatch(hl.dsp.window.move({{ {target}, x = {x}, y = {y} }}))")
    window.wait(lambda c: (*c["at"], *c["size"]) == (x, y, w, h), f"at {x},{y} {w}x{h}")


def remembered(desk, wm_class):
    return wait_until(lambda: desk.bench.remembered().get(wm_class), what=f"{wm_class} to be remembered")


def test_wayland_window_comes_back_where_it_was(desk):
    name = desk.name("memory")
    window = desk.wayland(wm_class=name)
    move(desk, window, 300, 200, 640, 400)
    window.close()
    assert remembered(desk, name)[2:] == ["300", "200", "640", "400"]

    again = desk.wayland(wm_class=name)
    again.wait(lambda c: (*c["at"], *c["size"]) == (300, 200, 640, 400), "back where it was")


def test_window_closed_maximised_is_remembered_as_it_stood(desk):
    name = desk.name("memory")
    window = desk.wayland(wm_class=name)
    move(desk, window, 250, 150, 600, 380)
    desk.place(window, "maximized")
    window.wait(lambda c: "maximized" in c["tags"], "maximised")
    window.close()
    assert remembered(desk, name)[2:] == ["250", "150", "600", "380"]


def test_window_as_large_as_the_screen_is_not_remembered_that_large(desk):
    name = desk.name("memory")
    _, _, w, h = desk.bench.work_area
    window = desk.wayland(wm_class=name, width=w, height=h)
    window.wait(lambda c: "maximized" in c["tags"], "maximised as it opened")
    window.close()
    entry = remembered(desk, name)
    assert (int(entry[4]), int(entry[5])) != (w, h)


def test_x11_window_is_not_remembered_and_an_old_entry_goes(desk):
    name = desk.name("memory")
    # What an older version remembered for it.
    desk.bench.geometry_file.parent.mkdir(parents=True, exist_ok=True)
    desk.bench.geometry_file.write_text(f"{name}\t\tBENCH\t0\t0\t1920\t1028\n")
    desk.bench.reload()

    window = desk.x11(wm_class=name, x=320, y=240, width=640, height=400)
    wait_until(lambda: name not in desk.bench.remembered(), what="the old entry to go")
    window.close()
    assert name not in desk.bench.remembered()
