"""The keys Blueberry binds, and the ones it must leave alone.

Alt+Tab picks the window as Alt is let go of, which the shell hears through a
bind on Alt's release. A plain bind like that swallowed Alt's press as well,
and Alt stopped reaching applications at all. Without being transparent it
went unheard after Tab, and the switcher waited for good. One in a submap of
its own never heard the release of an Alt pressed before the submap.
"""

import time

from bench.bench import wait_until


def switcher_up(desk) -> bool:
    return any(layer["namespace"] == "quickshell:switcher"
               for monitor in desk.bench.json("layers").values()
               for layers in monitor["levels"].values() for layer in layers)


def test_alt_reaches_applications(desk):
    window = desk.wayland()
    window.command("keys")
    kb = desk.keyboard
    kb.type(*kb.hold("Alt_L", "alt"), *kb.tap("f"), *kb.let_go("Alt_L", "alt"))
    # Gathered until Alt's release has come, the keys can arrive over more
    # than one asking.
    keys = []

    def all_arrived():
        keys.extend(window.command("keys")["keys"])
        return any(kind == "released" and name == "Alt_L" for kind, name, _ in keys)

    wait_until(all_arrived, what="keys to reach the window")
    assert ["pressed", "Alt_L", []] in keys
    assert ["pressed", "f", ["alt"]] in keys
    assert ["released", "Alt_L", []] in keys or ["released", "Alt_L", ["alt"]] in keys


def test_quick_alt_tab_goes_back_to_the_window_before(desk):
    first = desk.wayland()
    second = desk.wayland()
    wait_until(lambda: desk.active() == second.address, what="the second window to have the keyboard")
    kb = desk.keyboard
    kb.type(*kb.hold("Alt_L", "alt"), *kb.tap("Tab"), *kb.let_go("Alt_L", "alt"))
    wait_until(lambda: desk.active() == first.address, what="the window before to have the keyboard")
    time.sleep(0.3)
    assert not switcher_up(desk)


def test_held_alt_tab_shows_the_switcher_and_picks_on_letting_go(desk):
    first = desk.wayland()
    second = desk.wayland()
    wait_until(lambda: desk.active() == second.address, what="the second window to have the keyboard")
    kb = desk.keyboard
    kb.type(*kb.hold("Alt_L", "alt"), *kb.tap("Tab"), *kb.wait(400), *kb.let_go("Alt_L", "alt"))
    wait_until(lambda: desk.active() == first.address, what="the picked window to have the keyboard")
    wait_until(lambda: not switcher_up(desk), what="the switcher to go")


def test_alt_let_go_of_with_tab_still_down_picks(desk):
    # As a hand does it. A bind on Alt's release does not fire while Tab is
    # down, and the switcher stayed up until Alt was next tapped.
    first = desk.wayland()
    second = desk.wayland()
    wait_until(lambda: desk.active() == second.address, what="the second window to have the keyboard")
    keys = desk.real_keys()
    keys.press("alt")
    keys.press("tab")
    wait_until(lambda: switcher_up(desk), what="the switcher to come up")
    time.sleep(0.2)
    keys.release("alt")
    time.sleep(0.03)
    keys.release("tab")
    wait_until(lambda: desk.active() == first.address, what="the picked window to have the keyboard")
    wait_until(lambda: not switcher_up(desk), what="the switcher to go")


def test_quick_alt_let_go_of_with_tab_still_down_picks(desk):
    first = desk.wayland()
    second = desk.wayland()
    wait_until(lambda: desk.active() == second.address, what="the second window to have the keyboard")
    keys = desk.real_keys()
    keys.press("alt")
    keys.press("tab")
    keys.release("alt")
    keys.release("tab")
    wait_until(lambda: desk.active() == first.address, what="the window before to have the keyboard")
    time.sleep(0.3)
    assert not switcher_up(desk)


def test_tabbing_on_while_alt_is_held_stays_up_until_it_is_let_go_of(desk):
    first = desk.wayland()
    desk.wayland()
    third = desk.wayland()
    wait_until(lambda: desk.active() == third.address, what="the third window to have the keyboard")
    keys = desk.real_keys()
    keys.press("alt")
    keys.press("tab")
    wait_until(lambda: switcher_up(desk), what="the switcher to come up")
    keys.release("tab")
    time.sleep(0.3)
    assert switcher_up(desk), "the switcher went with Alt still held"
    keys.press("tab")
    keys.release("tab")
    keys.release("alt")
    wait_until(lambda: not switcher_up(desk), what="the switcher to go")
    wait_until(lambda: desk.active() == first.address, what="the second Tab to have moved on to the first window")


def test_alt_tab_in_quick_succession_never_hangs(desk):
    desk.wayland()
    desk.wayland()
    kb = desk.keyboard
    for pause in (1, 30, 90, 150, 200, 400):
        kb.type(*kb.hold("Alt_L", "alt"), *kb.tap("Tab"), *kb.wait(pause), *kb.let_go("Alt_L", "alt"))
    wait_until(lambda: not switcher_up(desk), what="the switcher to go")
