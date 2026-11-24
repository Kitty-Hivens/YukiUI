"""A window closed from under others goes without fading over them.

Hyprland draws windows going away after every floating one and orders them by
height only among themselves, so one closed while others stood over it faded
over them. The rules leave such a window unanimated as it closes, which
Hyprland then takes no picture of.
"""

import subprocess
import time

from PIL import Image

from bench.bench import OUTPUT
from bench.windows import IconWindow


def move(desk, window, x, y, w, h):
    target = f'window = "address:{window.address}"'
    desk.bench.eval(f"hl.dispatch(hl.dsp.window.resize({{ {target}, x = {w}, y = {h} }})) "
                    f"hl.dispatch(hl.dsp.window.move({{ {target}, x = {x}, y = {y} }}))")
    window.wait(lambda c: (*c["at"], *c["size"]) == (x, y, w, h), f"at {x},{y} {w}x{h}")


def raise_(desk, window):
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{window.address}" }}))')


def covered(desk, window) -> bool:
    return desk.bench.lua_value(f'YUKI_COVERED("{window.address}")') == "true"


def test_which_windows_stand_over_one_is_read_off_the_drawing_order(desk):
    lower = desk.wayland("lower")
    upper = desk.wayland("upper")
    apart = desk.wayland("apart")
    move(desk, lower, 200, 150, 600, 400)
    move(desk, upper, 500, 300, 600, 400)
    move(desk, apart, 1300, 150, 400, 300)
    raise_(desk, upper)
    assert covered(desk, lower) and not covered(desk, upper) and not covered(desk, apart)
    raise_(desk, lower)
    assert covered(desk, upper) and not covered(desk, lower)

    # Out of sight, it stands over nothing.
    desk.shell.call("minimize", "toggle", lower.address)
    lower.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised")
    assert not covered(desk, upper)


def shot(desk, path) -> Image.Image:
    subprocess.run(["grim", "-o", OUTPUT, str(path)], check=True, env=desk.bench.environment())
    return Image.open(path).convert("RGB")


def test_it_does_not_fade_over_what_stands_over_it(desk, tmp_path):
    # White under a window of another colour, closed with its fade made slow.
    lower = IconWindow(desk.bench, desk.name("white"))
    desk.windows.append(lower)
    upper = desk.wayland("upper")
    move(desk, upper, 300, 200, 900, 600)
    size = lower.client()["size"]
    desk.bench.eval(f'hl.dispatch(hl.dsp.window.move({{ window = "address:{lower.address}", x = 500, y = 400 }}))')
    lower.wait(lambda c: c["at"] == [500, 400], "under the other")
    raise_(desk, upper)
    time.sleep(0.5)
    centre = (500 + size[0] // 2, 400 + size[1] // 2)
    before = shot(desk, tmp_path / "before.png").getpixel(centre)

    desk.bench.eval('hl.config({ animations = { enabled = true } }) hl.animation({ leaf = "windowsOut", enabled = true, speed = 30, bezier = "default" }) '
                    'hl.animation({ leaf = "fadeOut", enabled = true, speed = 30, bezier = "default" })')
    try:
        lower.close()
        time.sleep(0.3)
        during = shot(desk, tmp_path / "during.png").getpixel(centre)
    finally:
        desk.bench.eval("hl.config({ animations = { enabled = false } })")
    assert during == before, "the window that went was drawn over the one above it"
