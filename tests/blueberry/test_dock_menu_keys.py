"""The keys of the dock's menus.

The menus took the mouse alone. Opened, a menu now takes the keyboard, the way
the dock takes it for a password field in quick settings: Up and Down go from
entry to entry past separators and round from one end to the other, Home and
End go to the ends, a letter to the next entry starting with it, Enter chooses,
Escape closes, and Right and Left go into a submenu opened in place and back.
Opened with the mouse, nothing is picked until a key is pressed.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import Keyboard

PROBE = SHELL / "benchDockMenuKeysProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_dock_menu_keys.py for a test run, and removed after it.
ShellRoot {
    id: probe

    ExDock {}

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
        const dock = ExStates.dockWindows[0];
        if (!dock || !item || !item.visible)
            return "";
        const at = dock.place(item);
        return JSON.stringify({ x: Math.round(at.x), y: Math.round(at.y), width: Math.round(at.w), height: Math.round(at.h) });
    }
    readonly property var status: probe.find(ExStates.dockWindows[0]?.contentItem, item => item.clockButton !== undefined && item.statusButton !== undefined)

    IpcHandler {
        target: "menuKeysProbe"
        function clock(): string {
            return probe.rect(probe.status?.clockButton);
        }
        function launcher(): string {
            return probe.rect(probe.find(ExStates.dockWindows[0]?.contentItem, item => item.kind === "flat" && item.rightClicked !== undefined && item.implicitWidth > 0 && probe.find(item, child => child.text === "apps") !== null));
        }
        function open(): bool {
            return ExStates.openPopup?.open ?? false;
        }
        // The entry the keys are on, by its text, or empty.
        function current(): string {
            return ExStates.openPopup?.menuKeys?.current?.text ?? "";
        }
        function silent(): bool {
            return Notifications.silent;
        }
        function inSession(): bool {
            return ExStates.openPopup?.inSession ?? false;
        }
    }
}
"""


@pytest.fixture
def dock(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dock", "activate", "99"), own_bus=True)
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the dock reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def centre(bench, shell, name):
    import json
    r = json.loads(wait_until(lambda: shell.call("menuKeysProbe", name), what=f"the {name} on the dock"))
    layer = next(layer for data in json.loads(bench.hyprctl("layers", "-j")).values()
                 for layers in data["levels"].values() for layer in layers if layer["namespace"] == "quickshell:dock")
    # The dock places its items as if its window met the screen's edge.
    return r["x"] + r["width"] // 2, r["y"] + layer["y"] + layer["h"] - 1080 + r["height"] // 2


def right_click(desk, x, y):
    pointer = desk.pointer()
    pointer.move(x - 20, y)
    pointer.move(x, y)
    pointer.click(x, y, button="right")
    # Away from the menu, so the pointer picks nothing in it.
    pointer.move(200, 200)


def press(bench, *keys):
    keyboard = Keyboard(bench)
    for key in keys:
        keyboard.type(*Keyboard.tap(key))
        time.sleep(0.1)


def picked(dock):
    return dock.call("menuKeysProbe", "current")


def test_the_keys_go_through_a_menu_opened_with_the_mouse(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "clock"))
    wait_until(lambda: dock.call("menuKeysProbe", "open") == "true", what="the clock's menu")
    time.sleep(0.4)
    assert picked(dock) == "", "something was picked before a key was pressed"
    silent = dock.call("menuKeysProbe", "silent") == "true"
    first = "Turn off do not disturb" if silent else "Turn on do not disturb"

    press(bench, "Down")
    wait_until(lambda: picked(dock) == first, what=f"the first entry picked, last {picked(dock)}")
    # Past the separator under it.
    press(bench, "Down")
    assert picked(dock) == "Notification settings"
    press(bench, "Down", "Down")
    assert picked(dock) == first, "it did not go round from the end to the start"
    press(bench, "Up")
    assert picked(dock) == "Date and time settings", "it did not go round from the start to the end"
    press(bench, "Home")
    assert picked(dock) == first
    press(bench, "End")
    assert picked(dock) == "Date and time settings"
    press(bench, "n")
    assert picked(dock) == "Notification settings"

    press(bench, "Home", "Return")
    wait_until(lambda: dock.call("menuKeysProbe", "open") == "false", what="the menu to close as an entry is chosen")
    wait_until(lambda: (dock.call("menuKeysProbe", "silent") == "true") != silent, what="do not disturb to be switched")


def test_escape_closes_a_menu(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "clock"))
    wait_until(lambda: dock.call("menuKeysProbe", "open") == "true", what="the clock's menu")
    time.sleep(0.4)
    press(bench, "Escape")
    wait_until(lambda: dock.call("menuKeysProbe", "open") == "false", what="the menu to close")


def test_right_and_left_go_into_a_submenu_and_back(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "launcher"))
    wait_until(lambda: dock.call("menuKeysProbe", "open") == "true", what="the launcher's menu")
    time.sleep(0.4)
    press(bench, "End", "Up")
    assert picked(dock) == "Shut down or sign out"
    press(bench, "Right")
    wait_until(lambda: dock.call("menuKeysProbe", "inSession") == "true", what="the session entries")
    # Its first entry picked, the way back out.
    wait_until(lambda: picked(dock) == "Shut down or sign out", what="the first entry of the submenu picked")
    press(bench, "Left")
    wait_until(lambda: dock.call("menuKeysProbe", "inSession") == "false", what="back out of the submenu")
    wait_until(lambda: picked(dock) == "Power", what=f"the first entry picked again, last {picked(dock)}")
    press(bench, "Escape")
