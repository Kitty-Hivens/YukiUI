"""The snipping tool: a rectangle drawn, a window clicked, and the keys that open it.

What is taken is cut from the screen as it was when the tool opened, and goes
to the clipboard, which on the bench is the nested compositor's own.
"""

import io
import subprocess
import time
import urllib.parse

import pytest
from PIL import Image

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchScreenSnipProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.experimental.screenSnip

// Written by tests/experimental/test_screen_snip.py for a test run, and removed after it.
ShellRoot {
    ExScreenSnip {
        id: snip
    }
    IpcHandler {
        target: "snipProbe"
        function ready(): bool {
            return true;
        }
        function setArea(area: string): void {
            snip.area = area;
        }
        function media(): string {
            return snip.media;
        }
    }
}
"""


@pytest.fixture
def snip(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("snipProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def is_open(shell) -> bool:
    return shell.call("region", "isOpen") == "true"


def snip_layer_up(bench) -> bool:
    import json
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            if any(layer["namespace"] == "quickshell:snip" for layer in layers):
                return True
    return False


def open_tool(bench, shell, how="screenshot"):
    # Nothing left on the clipboard by an earlier test to be read as this one's.
    subprocess.run(["wl-copy", "--clear"], env=bench.environment(), check=True)
    shell.call("region", how)
    wait_until(lambda: is_open(shell) and snip_layer_up(bench), what="the snipping tool to come up")
    time.sleep(0.5)


def clipboard_image(bench) -> Image.Image:
    def read():
        result = subprocess.run(["wl-paste", "--type", "image/png"], env=bench.environment(), capture_output=True)
        return result.stdout if result.returncode == 0 and result.stdout else None
    return Image.open(io.BytesIO(wait_until(read, timeout=5, what="a picture on the clipboard")))


def test_a_drawn_rectangle_goes_to_the_clipboard(bench, desk, snip):
    window = desk.wayland()
    time.sleep(1.0)
    x, y, w, h = window.rect
    open_tool(bench, snip)
    pointer = desk.pointer()
    # Inside the window, which is drawn light, so the picture is of it and
    # not of the tool's dimming over it.
    left, top = x + 100, y + 120
    pointer.move(left, top)
    pointer.press()
    pointer.glide(left + 300, top + 200)
    # What shows inside the rectangle while it is drawn is the window as it
    # is. A frozen screen copy taken as the tool showed held the tool's own
    # dimming, and the rectangle showed it dimmed once over.
    time.sleep(0.3)
    shown = Image.open(io.BytesIO(subprocess.run(["grim", "-o", OUTPUT, "-"], env=bench.environment(),
                                                 capture_output=True, check=True).stdout)).convert("RGB")
    r, g, b = shown.getpixel((left + 150, top + 100))
    assert min(r, g, b) > 200, f"the rectangle shows the window dimmed: {(r, g, b)}"
    pointer.release()
    wait_until(lambda: not is_open(snip), what="the tool to close")
    picture = clipboard_image(bench)
    assert picture.size == (300, 200)
    r, g, b = picture.convert("RGB").getpixel((150, 100))
    assert min(r, g, b) > 200, f"the picture is dimmed: {(r, g, b)}"
    # And as the file it is kept in, for a program that takes files: with no
    # folder set for screenshots, in the bench's cache.
    # Never as text: a browser's text field takes text before a picture, and
    # pasted the path.
    types = subprocess.run(["wl-paste", "--list-types"], env=bench.environment(), capture_output=True, text=True).stdout.split()
    assert types == ["image/png", "text/uri-list", "x-special/gnome-copied-files"], types
    link = subprocess.run(["wl-paste", "--no-newline", "--type", "text/uri-list"], env=bench.environment(),
                          capture_output=True, text=True).stdout.strip()
    path = urllib.parse.unquote(link.removeprefix("file://"))
    assert path.startswith(str(bench.cache_home)) and Image.open(path).size == (300, 200), path


def test_a_clicked_window_is_taken_whole(bench, desk, snip):
    window = desk.wayland()
    time.sleep(1.0)
    x, y, w, h = window.rect
    open_tool(bench, snip)
    snip.call("snipProbe", "setArea", "window")
    pointer = desk.pointer()
    pointer.move(x + w // 2 - 40, y + h // 2 - 40)
    pointer.click(x + w // 2, y + h // 2)
    wait_until(lambda: not is_open(snip), what="the tool to close")
    assert clipboard_image(bench).size == (w, h)


def test_escape_closes_it_and_takes_nothing(bench, desk, snip):
    open_tool(bench, snip)
    desk.keyboard.type(*desk.keyboard.tap("Escape"))
    wait_until(lambda: not is_open(snip), what="Escape to close the tool")
    assert snip.call("region", "lastCommand") == "[]"


def test_print_screen_opens_it(bench, desk, snip):
    # Bound in the environment's compositor rules in place of the shared bind,
    # which put the whole screen on the clipboard.
    desk.keyboard.type(*desk.keyboard.tap("Print"))
    wait_until(lambda: is_open(snip), what="Print Screen to open the snipping tool")
    assert snip.call("snipProbe", "media") == "image"
    snip.call("region", "close")


def test_the_record_key_opens_it_for_a_video(bench, desk, snip):
    open_tool(bench, snip, "record")
    assert snip.call("snipProbe", "media") == "video"
    snip.call("region", "close")
