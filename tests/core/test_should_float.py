"""hl.plugin.minimize.should_float: whether a window would float if it opened now.

An environment that tiles asks it of every floating window another left, as
it comes up. It answers from Hyprland's own judgement as the window opened and
from the rules loaded now, and only reads the rules: applied again to the
window asked about, a rule that toggles a tag flipped it at every question.
"""

import time


def should_float(bench, window) -> str:
    return bench.lua_value(f'hl.plugin.minimize.should_float("{window.address}")')


def test_it_follows_the_rules_loaded(bench, desk):
    # The bench runs under the experimental environment's rules, which float
    # every window, and a rule after them tiles these.
    bench.eval('hl.window_rule({ match = { class = "^(bench\\\\.tiled.*)$" }, float = false, tile = true })')
    floating = desk.wayland()
    tiled = desk.wayland(stem="tiled")
    time.sleep(0.8)
    assert should_float(bench, floating) == "true"
    assert should_float(bench, tiled) == "false"


def test_asking_changes_nothing_on_the_window(bench, desk):
    bench.eval('hl.window_rule({ match = { class = "^(bench\\\\.toggled.*)$" }, tag = "ruled" })')
    window = desk.wayland(stem="toggled")
    # A tag a rule gives is listed with a star.
    window.wait(lambda c: "ruled*" in c["tags"], "tagged by its rule")
    for _ in range(3):
        should_float(bench, window)
    assert "ruled*" in window.client()["tags"], "asking flipped the tag the rule gives"
