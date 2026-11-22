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
