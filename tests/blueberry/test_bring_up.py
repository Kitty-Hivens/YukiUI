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
    # The shell places a window that opens a moment later, and placed after
    # the move here it moved the window away from where the test stood it.
    time.sleep(0.5)
    for window, x in ((below, 100), (over, 300)):
        desk.bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{window.address}" }})) '
                        f'hl.dispatch(hl.dsp.window.move({{ window = "address:{window.address}", x = {x}, y = 100 }}))')
        window.wait(lambda c, x=x: c["at"] == [x, 100], f"to stand at {x}, 100")
    # Over in front, as the one opened last.
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{over.address}" }})) '
                    f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{over.address}" }}))')
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
                    f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{over.address}" }}))')
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
    # Used before, as a running application has been: Hyprland 0.57 gives a
    # window a token to bring itself up only against input it has really had.
    # Its part that the other window leaves in sight.
    pointer.click(150, 300)
    wait_until(lambda: desk.active() == below.address, what="the application to have been used")
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{over.address}" }})) '
                    f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{over.address}" }}))')
    assert in_front(desk, pointer) == over.address
    below.command("present")
    wait_until(lambda: desk.active() == below.address, what="the application to have focus")
    assert in_front(desk, pointer) == below.address, "the application has focus but stays behind"
