"""Where a window comes back when its application opens again.

A Wayland application cannot place its own window, so the compositor rules
remember where the last window of each one stood. An X11 application places
itself, and is left to do so.

A window closed within seconds of opening is not remembered, so that a splash
screen is not taken for its application's last window. The tests here close
their windows sooner than that, so the rules are told to remember any window,
and the test of the limit sets a short one of its own.
"""

import time

import pytest

from bench.bench import wait_until


@pytest.fixture(autouse=True)
def any_lifetime(desk):
    desk.bench.eval("YUKI_GEOMETRY_MIN_LIFE = -1")


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


def test_the_welcome_opens_at_its_own_size_and_is_not_remembered(desk):
    # It sizes itself to the screen it opens on. What an older version
    # remembered for it, from a screen in another mode, kept it a third of a
    # larger one.
    desk.bench.geometry_file.parent.mkdir(parents=True, exist_ok=True)
    desk.bench.geometry_file.write_text("org.quickshell\tBlueberry Welcome\tBENCH\t800\t360\t500\t300\n")
    desk.bench.reload()

    window = desk.wayland(wm_class="org.quickshell", title="Blueberry Welcome", width=900, height=600)
    window.wait(lambda c: tuple(c["size"]) == (900, 600), "at the size it asked for")
    move(desk, window, 120, 80, 700, 500)
    window.close()

    again = desk.wayland(wm_class="org.quickshell", title="Blueberry Welcome", width=900, height=600)
    again.wait(lambda c: tuple(c["size"]) == (900, 600), "at the size it asked for again, not where it was closed")


def test_another_shell_window_is_still_remembered(desk):
    window = desk.wayland(wm_class="org.quickshell", title="Blueberry Settings", width=900, height=600)
    move(desk, window, 120, 80, 700, 500)
    window.close()
    wait_until(lambda: desk.bench.geometry_file.exists() and any(line.startswith("org.quickshell\tBlueberry Settings\t")
                                                                   for line in desk.bench.geometry_file.read_text().splitlines()),
               what="the settings window to be remembered")


def test_a_window_closed_soon_after_it_opened_is_not_remembered(desk):
    # A splash screen closes before its application's main window opens, and
    # was taken for the last window of that application.
    desk.bench.eval("YUKI_GEOMETRY_MIN_LIFE = 2")
    name = desk.name("memory")
    splash = desk.wayland(wm_class=name)
    move(desk, splash, 300, 200, 300, 300)
    splash.close()
    time.sleep(0.5)
    assert name not in desk.bench.remembered()

    window = desk.wayland(wm_class=name)
    move(desk, window, 200, 120, 640, 400)
    time.sleep(3.2)
    window.close()
    assert remembered(desk, name)[2:6] == ["200", "120", "640", "400"]


def centred(desk, w, h):
    ax, ay, aw, ah = desk.bench.work_area
    return ax + (aw - w) // 2, ay + (ah - h) // 2


def test_a_centred_window_is_remembered_centred(desk):
    name = desk.name("memory")
    window = desk.wayland(wm_class=name)
    x, y = centred(desk, 600, 400)
    move(desk, window, x, y, 600, 400)
    window.close()
    assert remembered(desk, name)[-1] == "centered"

    again = desk.wayland(wm_class=name)
    again.wait(lambda c: (*c["at"], *c["size"]) == (x, y, 600, 400), "back in the middle")


def test_a_centred_window_comes_back_in_the_middle_of_another_screen(desk):
    # Remembered while the screen ran in another mode, where the middle was
    # elsewhere: the place written down is not where it opens.
    name = desk.name("memory")
    desk.bench.geometry_file.parent.mkdir(parents=True, exist_ok=True)
    desk.bench.geometry_file.write_text(f"{name}\t\tBENCH\t100\t60\t300\t300\tcentered\n")
    desk.bench.reload()

    window = desk.wayland(wm_class=name)
    x, y = centred(desk, 300, 300)
    window.wait(lambda c: (*c["at"], *c["size"]) == (x, y, 300, 300), f"in the middle at {x},{y}")
