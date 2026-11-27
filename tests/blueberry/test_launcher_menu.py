"""The menu of an application in the launcher.

A right click on an application, in the grid or among the results, opens its
menu at the pointer: its own actions, starting it, and pinning it to the
launcher and to the dock. What it picks is done, and it closes on Escape or a
press beside it, leaving the launcher open.
"""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchLauncherMenuProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.launcher

// Written by tests/blueberry/test_launcher_menu.py for a test run, and removed after it.
ShellRoot {
    id: probe

    PanelWindow {
        id: win
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "#f3f3f3"

        LauncherContent {
            id: content
            x: 100
            y: 100
            width: implicitWidth
            height: implicitHeight
            // As the launcher does each time it opens.
            Component.onCompleted: content.reset()
        }
    }

    function find(item, has, found) {
        if (!item)
            return found;
        if (has(item))
            found.push(item);
        for (const child of item.children ?? [])
            probe.find(child, has, found);
        return found;
    }

    function rect(item): string {
        if (!item)
            return "";
        const at = item.mapToItem(null, 0, 0);
        return JSON.stringify({ x: at.x, y: at.y, w: item.width, h: item.height });
    }

    IpcHandler {
        target: "launcherMenu"
        function ready(): bool {
            return Config.ready && AppSearch.list.length > 0 && probe.find(win.contentItem, item => item.desktopEntry !== undefined && item.visible, []).length > 0;
        }
        function unpinAll(): void {
            Config.options.launcher.pinnedApps = [];
        }
        // The tiles in sight, top to bottom and left to right.
        function tile(n: int): string {
            const tiles = probe.find(win.contentItem, item => item.desktopEntry !== undefined && item.visible && item.width > 0, [])
                .sort((a, b) => a.mapToItem(null, 0, 0).y - b.mapToItem(null, 0, 0).y || a.mapToItem(null, 0, 0).x - b.mapToItem(null, 0, 0).x);
            const found = tiles[n];
            return found ? JSON.stringify(Object.assign(JSON.parse(probe.rect(found)), { id: found.desktopEntry.id })) : "";
        }
        function menuOpen(): bool {
            return ExStates.launcherMenuOpen;
        }
        function menuItem(text: string): string {
            return probe.rect(probe.find(content.Window.window.contentItem, item => item.hasSubmenu !== undefined && item.text === text && item.visible, [])[0] ?? null);
        }
        function pinned(): string {
            return JSON.stringify([...Config.options.launcher.pinnedApps]);
        }
        function pinFirst(count: int): void {
            Config.options.launcher.pinnedApps = content.everything.slice(0, count).map(entry => entry.id);
        }
        function query(): string {
            return content.query;
        }
        function pick(): int {
            return content.pick;
        }
        function columns(): int {
            return content.columns;
        }
    }
}
"""


@pytest.fixture
def menu(desk):
    shell = Shell(desk.bench, probe=PROBE, source=SOURCE, ready=("launcherMenu", "ready"))
    try:
        shell.start()
        wait_until(lambda: shell.call("launcherMenu", "ready") == "true", timeout=10, what="the grid to fill")
        shell.call("launcherMenu", "unpinAll")
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        try:
            shell.call("launcherMenu", "unpinAll")
        except Exception:
            pass
        shell.stop()
        shell.remove_probe()


def middle(rect: dict) -> tuple[int, int]:
    return int(rect["x"] + rect["w"] / 2), int(rect["y"] + rect["h"] / 2)


def test_pinning_from_the_menu(desk, menu):
    pointer = desk.pointer()
    tile = json.loads(menu.call("launcherMenu", "tile", "0"))
    pointer.click(*middle(tile), button="right")
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "true", timeout=3, what="the menu to open")
    item = json.loads(menu.call("launcherMenu", "menuItem", "Pin to the launcher"))
    pointer.click(*middle(item))
    wait_until(lambda: json.loads(menu.call("launcherMenu", "pinned")) == [tile["id"]], timeout=3, what="the application to be pinned")
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "false", timeout=3, what="the menu to close once picked")


def test_escape_and_a_press_beside_close_the_menu(desk, menu):
    pointer = desk.pointer()
    tile = json.loads(menu.call("launcherMenu", "tile", "1"))
    pointer.click(*middle(tile), button="right")
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "true", timeout=3, what="the menu to open")
    desk.keyboard.type(*desk.keyboard.tap("Escape"))
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "false", timeout=3, what="Escape to close the menu")

    pointer.click(*middle(tile), button="right")
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "true", timeout=3, what="the menu to open again")
    pointer.click(20, 20)
    wait_until(lambda: menu.call("launcherMenu", "menuOpen") == "false", timeout=3, what="a press beside it to close the menu")


def test_the_keyboard_stays_with_the_search(desk, menu):
    keys = desk.keyboard
    keys.type(*keys.tap("Tab"), "abc")
    wait_until(lambda: menu.call("launcherMenu", "query") == "abc", timeout=3, what="typing after Tab to reach the search")
    # What was typed goes first.
    keys.type(*keys.tap("Escape"))
    wait_until(lambda: menu.call("launcherMenu", "query") == "", timeout=3, what="Escape to clear the search")


def test_the_arrows_move_from_the_pinned_row_into_the_grid_and_back(desk, menu):
    menu.call("launcherMenu", "pinFirst", "2")
    wait_until(lambda: len(json.loads(menu.call("launcherMenu", "pinned"))) == 2, timeout=3, what="two pins")
    columns = int(menu.call("launcherMenu", "columns"))
    keys = desk.keyboard
    keys.type(*keys.tap("Down"))
    wait_until(lambda: menu.call("launcherMenu", "pick") == "0", timeout=3, what="the first pin to be picked")
    keys.type(*keys.tap("Right"))
    wait_until(lambda: menu.call("launcherMenu", "pick") == "1", timeout=3, what="the second pin to be picked")
    # Down from the pinned row lands in the grid's first row, in the same column.
    keys.type(*keys.tap("Down"))
    wait_until(lambda: menu.call("launcherMenu", "pick") == str(2 + 1), timeout=3, what="the grid's first row to be picked")
    keys.type(*keys.tap("Down"))
    wait_until(lambda: menu.call("launcherMenu", "pick") == str(2 + 1 + columns), timeout=3, what="the next row to be picked")
    keys.type(*keys.tap("Up"), *keys.tap("Up"))
    wait_until(lambda: menu.call("launcherMenu", "pick") == "1", timeout=3, what="back up in the pinned row")
