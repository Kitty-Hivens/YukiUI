"""The mouse's side buttons as back and forward in the shell's windows.

A mouse sends them as the side and extra buttons, or as the back and forward
buttons proper, and both pairs are taken.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import Keyboard

from .test_file_picker import Answer, open_picker, picker_shell  # noqa: F401

PROBE = SHELL / "benchSettingsNavigationProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.settings

// Written by tests/blueberry/test_navigation_buttons.py for a test run, and removed after it.
ShellRoot {
    FloatingWindow {
        title: "benchSettings"
        implicitWidth: 900
        implicitHeight: 600
        ExSettings {
            id: settings
            anchors.fill: parent
        }
    }

    IpcHandler {
        target: "settingsProbe"
        function open(key: string): void {
            settings.open(key);
        }
        function here(): string {
            return settings.categoryKey;
        }
    }
}
"""


@pytest.fixture
def settings(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("settingsProbe", "here"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def press(pointer, x, y, button):
    # Brought in from aside: a window opened under a pointer that has not
    # moved since is not told the pointer is over it, and a press goes nowhere.
    pointer.move(x - 40, y - 40)
    pointer.move(x, y)
    pointer.press(button)
    pointer.release(button)


@pytest.mark.parametrize("back, forward", [("side", "extra"), ("back", "forward")])
def test_side_buttons_go_back_and_forward_in_settings(bench, desk, settings, back, forward):
    window = wait_until(lambda: next((c for c in bench.clients() if c["title"] == "benchSettings"), None),
                        what="the settings window")
    x, y = window["at"][0] + window["size"][0] // 2, window["at"][1] + window["size"][1] // 2
    for key in ("system", "devices", "apps"):
        settings.call("settingsProbe", "open", key)
    pointer = desk.pointer()

    press(pointer, x, y, back)
    wait_until(lambda: settings.call("settingsProbe", "here") == "devices", what="one page back")
    press(pointer, x, y, back)
    wait_until(lambda: settings.call("settingsProbe", "here") == "system", what="two pages back")
    press(pointer, x, y, forward)
    wait_until(lambda: settings.call("settingsProbe", "here") == "devices", what="one page forward")
    # Opening a page from one gone back to drops the ones after it.
    settings.call("settingsProbe", "open", "time")
    press(pointer, x, y, forward)
    time.sleep(0.3)
    assert settings.call("settingsProbe", "here") == "time"
    assert not settings.errors()


def test_back_button_proper_goes_back_in_the_file_picker(bench, desk, picker_shell, tmp_path):
    folder = tmp_path / "top"
    (folder / "inner").mkdir(parents=True)
    (folder / "a.txt").write_text("a")
    (folder / "inner" / "s.txt").write_text("s")
    answer = Answer(tmp_path / "back.fifo")
    picker = open_picker(bench, picker_shell, folder, tmp_path / "back.fifo")
    time.sleep(0.5)

    keyboard = Keyboard(bench)
    keyboard.type(*keyboard.hold("Control_L", "ctrl"), *keyboard.tap("l"), *keyboard.let_go("Control_L", "ctrl"))
    time.sleep(0.3)
    keyboard.type("inner", *keyboard.tap("Return"))
    time.sleep(0.8)
    press(desk.pointer(), picker["at"][0] + picker["size"][0] // 2, picker["at"][1] + picker["size"][1] // 2, "back")
    time.sleep(0.8)
    # Folders come first: past "inner" to "a.txt".
    keyboard.type(*keyboard.tap("Down"), *keyboard.tap("Down"))
    time.sleep(0.3)
    keyboard.type(*keyboard.tap("Return"))

    uris = answer.wait().get("uris", [])
    assert [uri.rsplit("/", 1)[-1] for uri in uris] == ["a.txt"]
