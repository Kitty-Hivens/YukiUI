"""Picture-in-picture does not take the keyboard on its own.

It took focus as it opened and at every request of the player, and Escape,
meant for the window in use, closed it. Kept from focus altogether, it took no
clicks either. The rules are read from the shared compositor rules as they are
written, which the bench does not load itself.
"""

import time

from bench.bench import REPO

RULES = REPO / "dots/.config/hypr/hyprland/rules.lua"


def pip_rules() -> list[str]:
    return [line for line in RULES.read_text().splitlines()
            if line.startswith("hl.window_rule(") and "Картинка в картинке" in line]


def test_picture_in_picture_opens_without_the_keyboard_and_takes_clicks(bench, desk):
    rules = pip_rules()
    assert any("no_initial_focus = true" in rule for rule in rules)
    assert any("focus_on_activate = false" in rule for rule in rules)
    for rule in rules:
        bench.eval(rule)

    window = desk.wayland()
    window.wait(lambda c: desk.active() == c["address"], what="the window in use to have the keyboard")
    pip = desk.wayland(stem="pip", title="Картинка в картинке", width=480, height=270)
    time.sleep(1.0)
    assert desk.active() == window.address, "picture-in-picture took the keyboard as it opened"

    # Escape goes to the window in use, not to the picture.
    pip.command("keys")
    desk.keyboard.type(*desk.keyboard.tap("Escape"))
    time.sleep(0.5)
    assert pip.command("keys")["keys"] == []

    # Its buttons take clicks.
    x, y, w, h = pip.rect
    pip.command("clicks")
    pointer = desk.pointer()
    pointer.move(x + w // 2 - 20, y + h // 2)
    pointer.click(x + w // 2, y + h // 2)
    time.sleep(0.5)
    assert pip.command("clicks")["clicks"] >= 1
