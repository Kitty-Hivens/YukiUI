"""The list of keys, opened by Super and /.

Its keys are read from the compositor by the binds' descriptions, so it shows
what a key was bound to rather than what it once was, and leaves out what is
bound to nothing.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchShortcutsProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.blueberry.shortcuts

// Written by tests/blueberry/test_shortcuts.py for a test run, and removed after it.
ShellRoot {
    ExShortcuts {}
}
"""

BINDS = """
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet" })
hl.bind("SUPER + SHIFT + W", function() end, { description = "Window: Close" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Window: Resize" })
hl.bind("CTRL + SUPER + Left", function() end, { description = "Workspace: Focus left" })
hl.bind("CTRL + SUPER + Right", function() end, { description = "Workspace: Focus right" })
hl.bind("SUPER + 1", function() end, { description = "Workspace: Focus 1" })
hl.bind("SUPER + A", function() end, { description = "Shell: Toggle left sidebar" })
"""


@pytest.fixture
def sheet(desk):
    desk.bench.eval(BINDS)
    shell = Shell(desk.bench, probe=PROBE, source=SOURCE, ready=("cheatsheet", "isOpen"))
    try:
        shell.start()
        wait_until(lambda: "Super" in shell.call("cheatsheet", "list"), what="the binds to be read")
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        desk.bench.reload()


def rows(shell) -> dict[str, str]:
    """The keys of each thing that is done, by its name."""
    return {line.split("\t")[1]: line.split("\t")[2] for line in shell.call("cheatsheet", "list").splitlines()}


def is_up(desk) -> bool:
    return any(layer["namespace"] == "quickshell:shortcuts"
               for monitor in desk.bench.json("layers").values()
               for layers in monitor["levels"].values() for layer in layers)


def test_the_keys_are_the_ones_bound(sheet):
    told = rows(sheet)
    assert told["Close a window"] == "Super Shift W"
    assert told["Resize a window"] == "Super right button"
    assert told["The workspace beside"] == "Super Ctrl arrow_back+arrow_forward"
    assert told["Go to a workspace"] == "Super 1 … 0"


def test_what_is_bound_to_nothing_is_left_out(sheet):
    told = rows(sheet)
    assert "Browser" not in told
    assert "Lock the screen" not in told
    # What the mouse does on the dock hangs on no bind.
    assert told["The application's menu"] == "right button"


def test_its_key_opens_and_closes_it_and_the_window_keeps_the_keyboard(sheet, desk):
    window = desk.wayland()
    wait_until(lambda: desk.active() == window.address, what="the window to have the keyboard")
    press = [*desk.keyboard.hold("Super_L", "logo"), *desk.keyboard.tap("slash"), *desk.keyboard.let_go("Super_L", "logo")]
    desk.keyboard.type(*press)
    wait_until(lambda: is_up(desk), what="the list to come up")
    time.sleep(0.4)
    desk.keyboard.type(*press)
    wait_until(lambda: not is_up(desk), what="the list to go")

    sheet.call("cheatsheet", "open")
    wait_until(lambda: is_up(desk), what="the list to come up again")
    time.sleep(0.4)
    desk.keyboard.type(*desk.keyboard.tap("Escape"))
    wait_until(lambda: not is_up(desk), what="Escape to put it away")
    time.sleep(0.5)
    window.command("keys")
    desk.keyboard.type(*desk.keyboard.tap("f"))
    keys = []

    def typed():
        keys.extend(window.command("keys")["keys"])
        return any(name == "f" for _, name, _ in keys)

    wait_until(typed, what="keys to reach the window again")


def test_a_click_beside_it_closes_it_and_one_on_it_does_not(sheet, desk):
    pointer = desk.pointer()
    sheet.call("cheatsheet", "open")
    wait_until(lambda: is_up(desk), what="the list to come up")
    time.sleep(0.6)
    pointer.click(960, 540)
    time.sleep(0.5)
    assert sheet.call("cheatsheet", "isOpen") == "true"
    pointer.click(20, 500)
    wait_until(lambda: not is_up(desk), what="the list to go")
