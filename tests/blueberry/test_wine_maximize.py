"""A Wine window is told the truth about being maximised.

Hyprland tells every Wayland window it is maximised as it maps, so a GTK window
draws no shadow of its own, and Blueberry leaves ordinary windows so. Wine
takes it literally and asks back to be maximised: osu's splash screen came up
filling the screen, and its fullscreen window asked dozens of times a second.
The minimize plugin now tells a Wayland window whose class ends in ".exe", as
Wine names them, that it is maximised only while the shell has it so, and the
shell takes such a window's requests at their word rather than as a toggle.

The window here is a GTK one given a Wine-like class: what is tested is what
it is told and how its requests are answered, which is the same for both.
"""

import time

from blueberry.test_maximize import area, believes, is_maximized


def wine_like(desk):
    return desk.wayland(wm_class=desk.name("wine") + ".exe")


def test_a_wine_window_is_not_told_it_is_maximised_as_it_opens(desk):
    window = wine_like(desk)
    window.wait_state(lambda s: believes(s) and "maximized" not in believes(s), "it is tiled but not maximised")
    assert "maximized" not in window.client()["tags"]


def test_its_requests_are_taken_at_their_word(desk):
    window = wine_like(desk)
    before = window.rect

    window.command("maximize")
    window.wait(lambda c: is_maximized(desk, c), "maximised as it asked")
    window.wait_state(lambda s: "maximized" in believes(s), "it is told it is maximised")

    # Asked again, as Wine does whenever it is told it is, it stays maximised:
    # taken as a toggle, the second request put it back.
    window.command("maximize")
    window.wait(lambda c: is_maximized(desk, c), "still maximised after asking again")

    window.command("unmaximize")
    client = window.wait(lambda c: not c["tags"], "put back as it asked")
    assert (*client["at"], *client["size"]) == before
    window.wait_state(lambda s: "maximized" not in believes(s), "it is told it is not maximised")


def test_an_ordinary_window_is_still_told_it_is_maximised(desk):
    window = desk.wayland()
    window.wait_state(lambda s: "maximized" in believes(s), "it is maximised, so it draws no shadow")
    x, y, w, h = area(desk)
    assert tuple(window.client()["size"]) != (w, h)


def test_a_minimise_asked_before_an_ordinary_window_shows_is_acted_on(desk):
    # The request reaches the compositor before the window does, and an
    # application asking it so is minimised as it opens.
    from bench.windows import IconWindow
    window = IconWindow(desk.bench, desk.name("early"), minimized=True)
    desk.windows.append(window)
    window.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised as it asked")


def test_a_minimise_asked_before_a_wine_window_shows_is_not_acted_on(desk):
    # Shown again from the notification area, a Windows window is still
    # minimised, and Wine asks for that as the window comes back: osu went
    # straight to the dock from its tray icon and came back out of fullscreen.
    from bench.windows import IconWindow
    window = IconWindow(desk.bench, desk.name("wine") + ".exe", minimized=True)
    desk.windows.append(window)
    for _ in range(6):
        time.sleep(0.5)
        assert not window.client()["workspace"]["name"].startswith("special:"), "the Wine window was minimised"


def test_a_wine_window_as_large_as_the_screen_is_not_maximised_as_it_opens(desk):
    # A Windows game between fullscreen and not, as osu is for a moment as it
    # comes back from the tray, was maximised by the rule for applications
    # that size themselves to the screen without saying so.
    x, y, w, h = area(desk)
    window = desk.wayland(wm_class=desk.name("wine") + ".exe", width=w, height=h + 40)
    for _ in range(5):
        time.sleep(0.5)
        assert "maximized" not in window.client()["tags"], "the Wine window was maximised"
