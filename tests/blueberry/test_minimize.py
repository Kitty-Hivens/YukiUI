"""Minimising: a window parked on a special workspace and brought back."""

import time

from bench.bench import wait_until


def test_application_asks_to_be_minimised_and_comes_back_where_it_stood(desk):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    before = window.rect

    window.command("minimize")
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")

    desk.shell.call("minimize", "toggle", window.address)
    client = window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")
    assert (*client["at"], *client["size"]) == before


def test_super_down_from_where_it_stands_minimises(desk):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    desk.shell.call("placement", "step", "down")
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")


def test_the_window_focus_passes_to_comes_up_in_front(desk):
    # The window used last before the minimised one is not always the one on
    # top. Given focus without being raised, it took the keys from behind the
    # window over it.
    pointer = desk.pointer()
    below = desk.wayland("below")
    over = desk.wayland("over")
    gone = desk.wayland("gone")
    # Moved once the shell has placed them, which it does a moment after they open.
    time.sleep(0.5)
    for window, x in ((below, 100), (over, 300), (gone, 900)):
        desk.bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{window.address}" }})) '
                        f'hl.dispatch(hl.dsp.window.move({{ window = "address:{window.address}", x = {x}, y = 100 }}))')
        window.wait(lambda c, x=x: c["at"] == [x, 100], f"to stand at {x}, 100")
    # Below used last but left under over, then the one to minimise in front.
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{below.address}" }}))')
    wait_until(lambda: desk.active() == below.address, what="below to have focus")
    desk.bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{gone.address}" }})) '
                    f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{gone.address}" }}))')
    wait_until(lambda: desk.active() == gone.address, what="gone to have focus")

    workspace = gone.client()["workspace"]["id"]
    desk.shell.call("minimize", "toggle", gone.address)
    gone.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    wait_until(lambda: desk.active() == below.address, what="focus to pass to below")

    # A click where below and over overlap lands on whichever is in front.
    pointer.click(600, 300)
    time.sleep(0.3)
    assert desk.active() == below.address, "the window given focus stayed behind another"
