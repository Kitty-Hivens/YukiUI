"""A Wine window that gives fullscreen up and covers the screen all the same.

Wine gives fullscreen up as its window stops covering the monitor and asks for
it back as it covers it again, unless it does both between two acknowledged
states: osu, coming back from the notification area, is for a fraction of a
millisecond a title bar short of the screen, and nothing asked for fullscreen
again after. It stood there as large as the screen, not fullscreen, over the
dock. The minimize plugin lets the request wait, for a window told the truth,
and drops it when the window still covers its monitor.
"""

import time

from bench.windows import IconWindow


def fullscreen(desk, suffix=".exe") -> IconWindow:
    window = IconWindow(desk.bench, desk.name("wine") + suffix, fullscreen=True)
    desk.windows.append(window)
    window.wait(lambda c: c["fullscreen"] == 2, "fullscreen as it asked")
    # Drawn at that size, as a game's window is.
    window.wait(lambda c: c["size"][0] > 1000, "as large as the screen")
    return window


def screen(desk) -> tuple[int, int]:
    monitor = next(m for m in desk.bench.monitors() if m["focused"])
    return monitor["width"], monitor["height"]


def test_one_that_still_covers_the_monitor_stays_fullscreen(desk):
    window = fullscreen(desk)
    width, height = screen(desk)
    window.leave_fullscreen(width, height)
    for _ in range(6):
        time.sleep(0.2)
        assert window.client()["fullscreen"] == 2, "it was taken out of fullscreen"


def test_one_that_has_shrunk_leaves(desk):
    window = fullscreen(desk)
    window.leave_fullscreen(800, 600)
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")


def test_an_ordinary_window_leaves_at_once(desk):
    window = fullscreen(desk, suffix="")
    width, height = screen(desk)
    window.leave_fullscreen(width, height)
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
