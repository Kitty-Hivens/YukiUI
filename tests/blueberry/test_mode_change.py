"""Placed windows follow a screen whose mode changes in place.

Hyprland says nothing on its event socket when a connected screen is given
another mode or scale, so a maximised window stayed as large as the old mode
until the display settings were kept and the config reloaded. And a window
that was minimised as the shell started was not learnt at all, so it stayed
the old size for good.
"""

import json

import pytest

from bench.bench import HEIGHT, OUTPUT, RESERVED_BOTTOM, WIDTH, wait_until

SMALL = (1600, 900)


def set_mode(bench, width: int, height: int):
    bench.eval(f'hl.monitor({{ output = "{OUTPUT}", mode = "{width}x{height}@60", position = "0x0", scale = 1, reserved = {{ bottom = {RESERVED_BOTTOM} }} }})')
    wait_until(lambda: (bench.monitors()[0]["width"], bench.monitors()[0]["height"]) == (width, height), what=f"the mode {width}x{height}")


@pytest.fixture
def mode(desk):
    try:
        yield lambda width, height: set_mode(desk.bench, width, height)
    finally:
        set_mode(desk.bench, WIDTH, HEIGHT)


def rect(client) -> tuple:
    return (*client["at"], *client["size"])


def area(width: int, height: int) -> tuple:
    return (0, 0, width, height - RESERVED_BOTTOM)


def test_a_maximised_window_follows_a_new_mode_at_once(desk, mode):
    window = desk.wayland()
    desk.place(window, "maximized")
    window.wait(lambda c: rect(c) == area(WIDTH, HEIGHT), "maximised")

    mark = desk.bench.events.mark()
    mode(*SMALL)
    window.wait(lambda c: rect(c) == area(*SMALL), "fitted to the new mode", timeout=2)
    assert not desk.bench.events.since(mark, "configreloaded"), "fitted only because the config was reloaded"

    mode(WIDTH, HEIGHT)
    window.wait(lambda c: rect(c) == area(WIDTH, HEIGHT), "fitted back to the old mode", timeout=2)


def test_a_window_minimised_across_a_restart_is_kept_and_fitted_as_it_comes_back(desk, mode):
    window = desk.wayland()
    desk.place(window, "maximized")
    window.wait(lambda c: rect(c) == area(WIDTH, HEIGHT), "maximised")
    desk.shell.call("minimize", "toggle", window.address)
    window.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised")

    desk.shell.restart()
    wait_until(lambda: window.address in json.loads(desk.shell.call("placement", "list")), timeout=5,
               what="the minimised window to be learnt as placed")

    mode(*SMALL)
    desk.shell.call("minimize", "toggle", window.address)
    window.wait(lambda c: not c["workspace"]["name"].startswith("special:") and rect(c) == area(*SMALL),
                "back, and fitted to the mode set while it was away", timeout=3)
    assert "maximized" in desk.bench.client(window.address)["tags"]
