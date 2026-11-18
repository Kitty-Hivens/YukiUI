"""The icons windows give themselves, handed to the shell by the window-icons plugin.

An application the shell finds no desktop entry for, Minecraft or a game, showed
a generic icon in the dock. A Wayland window gives its icon through
xdg-toplevel-icon, which Hyprland does not take, and an X11 window carries it in
_NET_WM_ICON, which only a client of the X server can read. The plugin takes
both and writes them where the shell keeps its runtime files, by the window's
class: a picture as a PNG, a name from the theme as text.
"""

import re

from PIL import Image

from bench.bench import wait_until
from bench.windows import IconWindow


def key(wm_class: str) -> str:
    return re.sub(r"[^a-z0-9._-]", "_", wm_class.lower())


def picture(desk, wm_class: str):
    path = desk.bench.window_icons / f"{key(wm_class)}.png"
    if not path.exists():
        return None
    image = Image.open(path).convert("RGBA")
    return image.size[0], image.getpixel((image.size[0] // 2, image.size[1] // 2))


def name(desk, wm_class: str):
    path = desk.bench.window_icons / f"{key(wm_class)}.name"
    return path.read_text() if path.exists() else None


def icon_window(desk, stem: str, **kwargs) -> IconWindow:
    window = IconWindow(desk.bench, desk.name(stem), **kwargs)
    desk.windows.append(window)
    return window


def test_an_x11_window_gives_its_icon_as_it_opens_and_after(desk):
    window = desk.x11(own=("icon",))
    # The largest of the pictures it gives, 32 of 16 and 32.
    wait_until(lambda: picture(desk, window.wm_class) == (32, (255, 0, 0, 255)), what="its red icon, 32 square")
    # Changed once shown, as Minecraft gives its icon after its window.
    window.command("icon 00ff00 24")
    wait_until(lambda: picture(desk, window.wm_class) == (24, (0, 255, 0, 255)), what="its new green icon, 24 square")


def test_a_wayland_window_gives_a_picture(desk):
    window = icon_window(desk, "picture", colour="0000ff", size=64)
    wait_until(lambda: picture(desk, window.wm_class) == (64, (0, 0, 255, 255)), what="its blue icon, 64 square")
    assert name(desk, window.wm_class) is None


def test_a_wayland_window_gives_a_name(desk):
    window = icon_window(desk, "named", name="utilities-terminal")
    wait_until(lambda: name(desk, window.wm_class) == "utilities-terminal", what="the name of its icon")
    assert picture(desk, window.wm_class) is None


def test_an_icon_given_before_the_window_shows_is_kept_for_it(desk):
    # Hyprland has no window for the toplevel yet, nor its class.
    window = icon_window(desk, "early", colour="00ff00", size=48, early=True)
    wait_until(lambda: picture(desk, window.wm_class) == (48, (0, 255, 0, 255)), what="the icon given early")


def test_an_icon_taken_back_is_gone(desk):
    window = icon_window(desk, "unset", name="utilities-terminal", colour="ff0000", size=32)
    wait_until(lambda: picture(desk, window.wm_class) is not None and name(desk, window.wm_class), what="its icon")
    window.command("unset")
    wait_until(lambda: picture(desk, window.wm_class) is None and name(desk, window.wm_class) is None, what="its icon gone")
