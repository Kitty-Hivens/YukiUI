"""A window's own request for fullscreen, as a browser's F11 makes it.

Fullscreen is Hyprland's, untouched by the shell: the window covers its whole
monitor, dock included, and leaving it puts the window back as it was, placed
or not.
"""

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
