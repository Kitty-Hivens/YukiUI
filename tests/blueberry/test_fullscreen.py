"""A window's own request for fullscreen, as a browser's F11 makes it.

Fullscreen is Hyprland's, untouched by the shell: the window covers its whole
monitor, dock included, and leaving it puts the window back as it was, placed
or not.
"""

import time

from .test_maximize import is_maximized


def screen(desk) -> tuple[int, int, int, int]:
    monitor = desk.bench.monitors()[0]
    return monitor["x"], monitor["y"], monitor["width"], monitor["height"]


def is_fullscreen(desk, client) -> bool:
    return client["fullscreen"] == 2 and (*client["at"], *client["size"]) == screen(desk)


def test_ordinary_window_goes_fullscreen_and_back(desk):
    window = desk.wayland()
    before = window.rect

    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")
    window.wait_state(lambda s: s["fullscreen"], "it is fullscreen")

    window.command("unfullscreen")
    client = window.wait(lambda c: c["fullscreen"] == 0 and c["fullscreenClient"] == 0, "out of fullscreen")
    assert (*client["at"], *client["size"]) == before
    assert not client["tags"]


def test_maximized_window_goes_fullscreen_and_back(desk):
    window = desk.wayland()
    desk.toggle_maximized(window)
    window.wait(lambda c: is_maximized(desk, c), "maximised")

    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")
    window.wait_state(lambda s: s["fullscreen"], "it is fullscreen")

    window.command("unfullscreen")
    window.wait(lambda c: is_maximized(desk, c), "maximised again")


def test_window_an_older_shell_maximized_goes_fullscreen(desk):
    # Maximised by a shell that marked it with Hyprland's fullscreen state,
    # which leaves the window's own fullscreen request with the window alone.
    window = desk.wayland()
    desk.place(window, "maximized")
    window.wait(lambda c: is_maximized(desk, c), "maximised")
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.fullscreen_state({{ internal = 0, client = 1, window = "address:{window.address}" }}))')
    window.wait(lambda c: c["fullscreenClient"] == 1, "marked the old way")

    desk.shell.restart()
    window.wait(lambda c: is_maximized(desk, c), "maximised, its states in step")

    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")


def test_window_opening_maximized_goes_fullscreen(desk):
    # A browser opens as large as the work area and is maximised by the shell
    # as it opens, then asks for fullscreen.
    _, _, w, h = desk.bench.work_area
    window = desk.wayland(width=w, height=h)
    window.wait(lambda c: is_maximized(desk, c), "maximised as it opened")

    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")
    window.wait_state(lambda s: s["fullscreen"], "it is fullscreen")


def test_a_fullscreen_spoof_outlives_a_shell_restart(desk):
    # Super+Alt+F tells a window it is fullscreen while the compositor keeps
    # it where it is. Only the old maximised mark is the shell's to clear.
    window = desk.wayland()
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.fullscreen_state({{ internal = 0, client = 3, window = "address:{window.address}" }}))')
    spoofed = window.wait(lambda c: c["fullscreenClient"] >= 2 and c["fullscreen"] == 0, "told it is fullscreen")["fullscreenClient"]
    desk.shell.restart()
    time.sleep(1.0)
    assert window.client()["fullscreenClient"] == spoofed


def leave_as_chromium_does(window):
    # Told it is maximised whatever its size, it asks for that again in the
    # same breath as it leaves fullscreen.
    window.command("unfullscreen")
    window.command("maximize")


def test_a_maximized_window_asking_to_be_so_as_it_leaves_fullscreen_stays_so(desk):
    window = desk.wayland()
    desk.toggle_maximized(window)
    window.wait(lambda c: is_maximized(desk, c), "maximised")
    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")

    leave_as_chromium_does(window)
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
    time.sleep(0.8)
    assert is_maximized(desk, window.client()), window.client()


def test_an_ordinary_window_asking_to_be_maximized_as_it_leaves_fullscreen_goes_back(desk):
    window = desk.wayland()
    before = window.rect
    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")

    leave_as_chromium_does(window)
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
    time.sleep(0.8)
    client = window.client()
    assert (*client["at"], *client["size"]) == before and not client["tags"], client


def test_a_window_asking_to_be_maximized_later_is(desk):
    window = desk.wayland()
    window.command("fullscreen")
    window.wait(lambda c: is_fullscreen(desk, c), "fullscreen over the whole screen")
    window.command("unfullscreen")
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
    time.sleep(0.5)
    window.command("maximize")
    window.wait(lambda c: is_maximized(desk, c), "maximised as it asked")
    # Asked again, as a program restoring its window does, it stays so.
    window.command("maximize")
    time.sleep(0.8)
    assert is_maximized(desk, window.client()), window.client()
