"""An X11 window the size of the whole screen, and what a window says of itself.

Hyprland keeps a new floating window off the room the dock reserves, so one as
tall as the screen it pushed up by the dock's height, its top past the edge of
the screen. A launcher that sized itself to the monitor rather than to the work
area stood so, its title bar out of reach: it is maximised, as any window
opening at most of the work area is.

A game opens the same size and draws by the size it asked for. Maximised under
it, its picture no longer met its window. It says what it is: it asks to bypass
the compositor, which the minimize plugin tags, and is left at its size with its
top back on the screen.

An application that remembers how it stood says so in its own _NET_WM_STATE
before it is shown, which Hyprland read only for being modal. The plugin asks
for the rest as a shown window would.
"""

import time

from bench.bench import RESERVED_BOTTOM


def maximized_in_work_area(client, w, h) -> bool:
    return "maximized" in client["tags"] and client["at"] == [0, 0] and client["size"] == [w, h - RESERVED_BOTTOM]


def test_an_x11_window_the_size_of_the_screen_is_maximised_into_the_work_area(desk):
    monitor = desk.bench.monitors()[0]
    w, h = monitor["width"], monitor["height"]
    window = desk.x11(x=0, y=0, width=w, height=h)
    window.wait(lambda c: maximized_in_work_area(c, w, h), "maximised into the work area")
    assert desk.placed()[window.address]["zone"] == "maximized"
    window.wait_state(lambda s: "_NET_WM_STATE_MAXIMIZED_VERT" in s["net_wm_state"], "it is maximised")
    # Nothing of it above the top of the screen, where Hyprland had pushed it.
    assert window.state()["geometry"][1] >= 0


def test_a_game_is_left_at_its_size_with_its_top_on_the_screen(desk):
    monitor = desk.bench.monitors()[0]
    w, h = monitor["width"], monitor["height"]
    window = desk.x11(x=0, y=0, width=w, height=h, own=("bypass",))
    window.wait(lambda c: "bypass" in c["tags"], "tagged as bypassing the compositor")
    window.wait(lambda c: c["at"] == [0, 0], "its top back on the screen")
    # Past both of the looks the shell takes at a window just opened.
    time.sleep(2.0)
    client = window.client()
    assert client["size"] == [w, h], f"resized to {client['size']}"
    assert client["at"] == [0, 0], f"moved to {client['at']}"
    assert "maximized" not in client["tags"]
    assert window.address not in desk.placed()


def test_a_game_goes_fullscreen_and_comes_back_the_same_size(desk):
    monitor = desk.bench.monitors()[0]
    w, h = monitor["width"], monitor["height"]
    window = desk.x11(x=0, y=0, width=w, height=h, own=("bypass",))
    window.wait(lambda c: c["at"] == [0, 0] and "bypass" in c["tags"], "on the screen, tagged")
    time.sleep(2.0)
    window.command("netstate add fullscreen")
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen")
    window.command("netstate remove fullscreen")
    client = window.wait(lambda c: c["fullscreen"] == 0, "back from fullscreen")
    assert client["size"] == [w, h], f"came back as {client['size']}"
    assert "maximized" not in client["tags"]


def test_a_window_that_opens_saying_it_is_maximised_is_maximised(desk):
    window = desk.x11(width=800, height=500, own=("maximized",))
    window.wait(lambda c: "maximized" in c["tags"], "maximised as it opened")
    window.wait_state(lambda s: "_NET_WM_STATE_MAXIMIZED_VERT" in s["net_wm_state"], "it is maximised")


def test_a_window_that_opens_saying_it_is_fullscreen_is_fullscreen(desk):
    window = desk.x11(width=800, height=500, own=("fullscreen",))
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen as it opened")
