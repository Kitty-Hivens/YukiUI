"""The game bar on Win+G: what opens it and puts it away, the widgets it shows,
where they are left, and what the capture widget takes.

The bench does not read the shared key binds, so a test binds Win+G itself, to
the shortcut the shared binds name.
"""

import io
import json
import subprocess
import time

import pytest
from PIL import Image

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchGameBarProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.experimental.gameBar
import qs.experimental.screenSnip

// Written by tests/experimental/test_game_bar.py for a test run, and removed after it.
ShellRoot {
    id: probe

    ExGameBar {
        id: bar
    }
    ExScreenSnip {}

    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }
    function rect(item) {
        if (!item || !item.visible)
            return "";
        const at = item.mapToItem(null, 0, 0);
        return JSON.stringify({ x: Math.round(at.x), y: Math.round(at.y), width: Math.round(item.width), height: Math.round(item.height) });
    }

    IpcHandler {
        target: "gameBarProbe"
        function ready(): bool {
            return Persistent.ready;
        }
        function widget(key: string): string {
            return probe.rect(probe.find(bar.window?.contentItem, item => item.key === key && item.saved !== undefined));
        }
        function homeButton(glyph: string): string {
            return probe.rect(probe.find(bar.window?.contentItem, item => item.glyph === glyph && item.toggled !== undefined));
        }
        function action(glyph: string): string {
            return probe.rect(probe.find(bar.window?.contentItem, item => item.glyph === glyph && item.subtitle !== undefined));
        }
        function saved(key: string): string {
            const place = Persistent.states.gameBar[key];
            return JSON.stringify({ x: place.x, y: place.y });
        }
        function resetPlaces(): void {
            for (const key of ["capture", "audio", "performance"]) {
                Persistent.states.gameBar[key].x = -1;
                Persistent.states.gameBar[key].y = -1;
            }
            Persistent.states.gameBar.open = ["capture", "audio", "performance"];
        }
        function gpuWatchers(): int {
            return ResourceUsage.gpuWatchers;
        }
    }
}
"""


@pytest.fixture
def bar(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("gameBarProbe", "ready"))
    try:
        shell.start()
        shell.call("gameBarProbe", "resetPlaces")
        yield shell
        assert not shell.errors(), "the game bar reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def is_open(shell) -> bool:
    return shell.call("gameBar", "isOpen") == "true"


def layer_up(bench, namespace="quickshell:gamebar") -> bool:
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            if any(layer["namespace"] == namespace for layer in layers):
                return True
    return False


def open_bar(bench, shell):
    shell.call("gameBar", "open")
    wait_until(lambda: is_open(shell) and layer_up(bench), what="the game bar to come up")
    # Laid out, and faded in.
    time.sleep(0.4)


def rect(shell, function, name) -> dict:
    text = wait_until(lambda: shell.call("gameBarProbe", function, name), what=f"{function} {name}")
    return json.loads(text)


def centre(r: dict) -> tuple[int, int]:
    return r["x"] + r["width"] // 2, r["y"] + r["height"] // 2


def test_win_g_opens_it_and_escape_hands_the_keyboard_back(bench, desk, bar):
    window = desk.wayland()
    window.wait(lambda c: desk.active() == c["address"], what="the window to have the keyboard")
    bench.eval('hl.bind("SUPER + G", hl.dsp.global("quickshell:overlayToggle"))')
    keyboard = desk.keyboard
    keyboard.type(*keyboard.hold("Super_L", "logo"), *keyboard.tap("g"), *keyboard.let_go("Super_L", "logo"))
    wait_until(lambda: is_open(bar) and layer_up(bench), what="Win+G to open the game bar")
    time.sleep(0.3)
    keyboard.type(*keyboard.tap("Escape"))
    wait_until(lambda: not is_open(bar) and not layer_up(bench), what="Escape to put the bar away")
    wait_until(lambda: desk.active() == window.address, what="the keyboard to go back to the window")


def test_a_click_beside_the_widgets_puts_it_away_and_one_on_them_does_not(bench, desk, bar):
    open_bar(bench, bar)
    pointer = desk.pointer()
    pointer.move(900, 700)
    # On a widget, between its controls.
    capture = rect(bar, "widget", "capture")
    pointer.click(capture["x"] + capture["width"] - 30, capture["y"] + capture["height"] - 12)
    time.sleep(0.3)
    assert is_open(bar), "a click on a widget put the bar away"
    # Beside every widget.
    pointer.click(960, 900)
    wait_until(lambda: not is_open(bar), what="a click beside the widgets to put the bar away")


def test_the_bar_shows_and_hides_a_widget(bench, desk, bar):
    open_bar(bench, bar)
    assert json.loads(bar.call("gameBar", "shown")) == ["capture", "audio", "performance"]
    pointer = desk.pointer()
    pointer.move(900, 700)
    button = rect(bar, "homeButton", "volume_up")
    pointer.click(*centre(button))
    wait_until(lambda: "audio" not in json.loads(bar.call("gameBar", "shown")), what="the audio widget to go")
    assert bar.call("gameBarProbe", "widget", "audio") == ""
    pointer.click(*centre(button))
    wait_until(lambda: bar.call("gameBarProbe", "widget", "audio") != "", what="the audio widget to come back")
    assert is_open(bar)


def test_a_widget_comes_back_where_it_was_left(bench, desk, bar):
    open_bar(bench, bar)
    before = rect(bar, "widget", "capture")
    pointer = desk.pointer()
    # The widget's name, along its top.
    grab_x, grab_y = before["x"] + 60, before["y"] + 20
    pointer.move(grab_x, grab_y)
    pointer.press()
    pointer.glide(grab_x + 300, grab_y + 150)
    pointer.release()
    moved = wait_until(lambda: (lambda r: r if r["x"] > before["x"] + 250 else None)(rect(bar, "widget", "capture")),
                       what="the widget to follow the drag")
    assert abs(moved["y"] - (before["y"] + 150)) <= 8
    assert json.loads(bar.call("gameBarProbe", "saved", "capture")) == {"x": moved["x"], "y": moved["y"]}
    bar.call("gameBar", "close")
    wait_until(lambda: not layer_up(bench), what="the bar to go")
    open_bar(bench, bar)
    again = rect(bar, "widget", "capture")
    assert (again["x"], again["y"]) == (moved["x"], moved["y"])


def test_a_screenshot_is_of_the_screen_without_the_bar(bench, desk, bar):
    window = desk.wayland()
    time.sleep(1.0)
    x, y, w, h = window.rect
    subprocess.run(["wl-copy", "--clear"], env=bench.environment(), check=True)
    open_bar(bench, bar)
    pointer = desk.pointer()
    pointer.move(900, 700)
    pointer.click(*centre(rect(bar, "action", "photo_camera")))
    wait_until(lambda: not is_open(bar), what="the bar to go before the picture")

    def read():
        result = subprocess.run(["wl-paste", "--type", "image/png"], env=bench.environment(), capture_output=True)
        return result.stdout if result.returncode == 0 and result.stdout else None
    picture = Image.open(io.BytesIO(wait_until(read, timeout=5, what="a picture on the clipboard"))).convert("RGB")
    assert picture.size == (1920, 1080)
    # The window is drawn light, and dimmed by the bar it would not be.
    r, g, b = picture.getpixel((x + w // 2, y + h // 2))
    assert min(r, g, b) > 200, f"the picture has the bar's dimming in it: {(r, g, b)}"
    assert "grim" in bar.call("gameBar", "lastCommand")


def test_snip_hands_over_to_the_snipping_tool(bench, desk, bar):
    open_bar(bench, bar)
    pointer = desk.pointer()
    pointer.move(900, 700)
    pointer.click(*centre(rect(bar, "action", "screenshot_region")))
    wait_until(lambda: bar.call("region", "isOpen") == "true" and layer_up(bench, "quickshell:snip"),
               what="the snipping tool to open")
    assert not is_open(bar)
    bar.call("region", "close")


def test_the_card_is_read_only_while_the_readings_are_shown(bench, desk, bar):
    open_bar(bench, bar)
    assert bar.call("gameBarProbe", "gpuWatchers") == "1"
    bar.call("gameBar", "setShown", "performance", "false")
    wait_until(lambda: bar.call("gameBarProbe", "gpuWatchers") == "0", what="the card to stop being read")
    bar.call("gameBar", "setShown", "performance", "true")
    wait_until(lambda: bar.call("gameBarProbe", "gpuWatchers") == "1", what="the card to be read again")
    bar.call("gameBar", "close")
    wait_until(lambda: bar.call("gameBarProbe", "gpuWatchers") == "0", what="the card to stop being read with the bar gone")
