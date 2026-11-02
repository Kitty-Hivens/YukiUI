"""A window picked from outside the dock comes up in front, not only focused.

Hyprland gives a floating window focus without raising it, so every way of
picking a window has to raise it too: Alt+Tab, quick or with its panel, and
the launcher.
"""

import time

import pytest

from bench.bench import wait_until


def overlapping(desk):
    below = desk.wayland("below")
    over = desk.wayland("over")
    for window, x in ((below, 100), (over, 300)):
        desk.bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{window.address}" }})) '
                        f'hl.dispatch(hl.dsp.window.move({{ window = "address:{window.address}", x = {x}, y = 100 }}))')
    return below, over


def in_front(desk, pointer) -> str:
    """The window a click where both stand lands on."""
    pointer.click(600, 300)
    time.sleep(0.3)
    return desk.active()


@pytest.mark.parametrize("panel", [False, True])
def test_alt_tab_brings_the_pick_up_in_front(desk, panel):
    pointer = desk.pointer()
    below, over = overlapping(desk)
    # Below used last, then over in front of it with focus: Alt+Tab picks below.
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{below.address}" }}))')
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{over.address}" }})) '
                    f'hl.dispatch(hl.dsp.window.bring_to_top({{ window = "address:{over.address}" }}))')
    wait_until(lambda: desk.active() == over.address, what="over to have focus")

    desk.shell.call("switcher", "next")
    if panel:
        time.sleep(0.5)
    desk.shell.call("switcher", "commit")
    wait_until(lambda: desk.active() == below.address, what="the pick to have focus")
    time.sleep(0.4)
    assert in_front(desk, pointer) == below.address, "the pick has focus but stays behind"


def test_a_running_application_started_again_comes_up_in_front(desk):
    # What the launcher does for an application already running: starts it,
    # and the running one asks the compositor to be brought up.
    pointer = desk.pointer()
    below, over = overlapping(desk)
    assert in_front(desk, pointer) == over.address
    below.command("present")
    wait_until(lambda: desk.active() == below.address, what="the application to have focus")
    assert in_front(desk, pointer) == below.address, "the application has focus but stays behind"
