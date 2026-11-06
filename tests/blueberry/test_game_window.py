"""A game is left at the size it asked for.

A window as large as the whole screen is no application sizing itself to the room
it has: Steam stops short of the dock or runs past it, and is maximised for that,
while a game opens exactly the size of the screen and goes fullscreen a moment
later. Fitted to the work area on the way, it was resized and told it was
maximised under its own feet, and a game draws by the size it believes it has.
"""

import time

from bench.bench import wait_until


def test_an_x11_window_the_size_of_the_screen_is_left_alone(desk):
    monitor = desk.bench.monitors()[0]
    w, h = monitor["width"], monitor["height"]
    window = desk.x11(x=0, y=0, width=w, height=h)
    wait_until(lambda: window.client()["size"] == [w, h], what="the window at the size it asked for")
    # Past both of the looks the shell takes at a window just opened.
    time.sleep(2.0)
    client = window.client()
    assert client["size"] == [w, h], f"resized to {client['size']}"
    assert "maximized" not in client["tags"]
    assert window.address not in desk.placed()


def test_it_goes_fullscreen_and_comes_back_the_same_size(desk):
    monitor = desk.bench.monitors()[0]
    w, h = monitor["width"], monitor["height"]
    window = desk.x11(x=0, y=0, width=w, height=h)
    time.sleep(2.0)
    window.command("netstate add fullscreen")
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen")
    window.command("netstate remove fullscreen")
    client = window.wait(lambda c: c["fullscreen"] == 0, "back from fullscreen")
    assert client["size"] == [w, h], f"came back as {client['size']}"
    assert "maximized" not in client["tags"]
