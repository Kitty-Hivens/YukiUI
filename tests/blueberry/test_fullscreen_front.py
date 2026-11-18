"""A fullscreen window focused again comes back over the windows let over it.

A window focused while another on its workspace is fullscreen is let draw over
it, and Hyprland keeps it so until a window is made fullscreen again. A browser
brought up over a fullscreen terminal stayed over it: neither Alt+Tab nor a
click on the dock brought the terminal back to the front. The minimize plugin
puts the others back under the fullscreen window as it is focused again,
leaving a pinned window, a picture in picture, over it.
"""

import time


def over_fullscreen(bench, window) -> str:
    return bench.lua_value(
        f'(function() for _, w in ipairs(hl.get_windows()) do if w.address == "{window.address}" then return w.allowed_over_fullscreen end end end)()')


def focus(bench, window):
    bench.eval(f'hl.dispatch(hl.dsp.focus({{ window = "address:{window.address}" }}))')


def test_a_fullscreen_window_focused_again_is_over_the_others(desk):
    bench = desk.bench
    terminal = desk.wayland("terminal")
    browser = desk.wayland("browser")
    pinned = desk.wayland("pip")
    bench.eval(f'hl.dispatch(hl.dsp.window.pin({{ action = "enable", window = "address:{pinned.address}" }}))')
    bench.eval(f'hl.dispatch(hl.dsp.window.fullscreen({{ mode = "fullscreen", action = "toggle", window = "address:{terminal.address}" }}))')
    terminal.wait(lambda c: c["fullscreen"] == 2, "fullscreen")
    assert over_fullscreen(bench, browser) == "false"

    focus(bench, browser)
    time.sleep(0.3)
    assert over_fullscreen(bench, browser) == "true", "the browser was not let over the fullscreen window"

    focus(bench, terminal)
    time.sleep(0.3)
    assert terminal.client()["fullscreen"] == 2, "the terminal left fullscreen"
    assert over_fullscreen(bench, browser) == "false", "the browser stayed over the fullscreen terminal"
    # A pinned window keeps its place over everything.
    assert pinned.client()["pinned"]
