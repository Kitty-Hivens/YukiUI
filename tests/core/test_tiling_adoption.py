"""What an environment that tiles does with the floating windows another left.

The Lua it runs as it comes up in another's place is taken from
core/TilingAdoption.qml and run here as the environment runs it: the bench
brings up no environments, so there is no switch to make.
"""

import re
import time

from bench.bench import SHELL

LUA = re.search(r"lua: `(.*?)`", (SHELL / "core/TilingAdoption.qml").read_text(), re.S).group(1)


def test_a_floating_window_that_would_tile_is_tiled_and_a_pinned_one_kept(bench, desk):
    bench.eval('hl.window_rule({ match = { class = "^(bench\\\\.tiled.*)$" }, float = false, tile = true })')
    left = desk.wayland(stem="tiled")
    pinned = desk.wayland(stem="tiled")
    time.sleep(0.8)
    # Floated by hand, as the environment before left them.
    for window in (left, pinned):
        bench.eval(f'hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{window.address}" }}))')
    bench.eval(f'hl.dispatch(hl.dsp.window.pin({{ action = "enable", window = "address:{pinned.address}" }}))')
    time.sleep(0.4)
    assert left.client()["floating"] and pinned.client()["floating"]
    bench.eval(LUA)
    left.wait(lambda c: not c["floating"], "tiled")
    time.sleep(0.3)
    assert pinned.client()["floating"], "a pinned window was tiled"


def test_a_window_the_rules_float_stays_floating(bench, desk):
    # The bench runs under Blueberry's rules, which float
    # every window.
    window = desk.wayland()
    time.sleep(0.5)
    bench.eval(LUA)
    time.sleep(0.5)
    assert window.client()["floating"]
