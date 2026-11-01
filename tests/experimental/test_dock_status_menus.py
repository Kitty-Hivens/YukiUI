"""A right click on the status block opens the menu of the part clicked.

The parts of the block took only the left button, so a right click fell
through to the dock under them and opened the dock's own menu over the clock.
Each part now has its own, and each icon of the three in the middle its own,
as in the Windows corner.

The sound icon's menu also leads to the sound page of quick settings, which
the arrow at the end of the volume opens as well: the device sound comes out
of, and how loud each application plays.
"""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockStatusMenuProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.experimental
import qs.experimental.dock

// Written by tests/experimental/test_dock_status_menus.py for a test run, and removed after it.
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
        target: "statusMenuProbe"
        function clock(): string {
            return probe.rect(probe.status?.clockButton);
        }
        function volume(): string {
            return probe.rect(probe.find(probe.status, item => item.ghost !== undefined && item.name === ExStatusGlyphs.volumeGlyph));
        }
        function plate(): string {
            return probe.rect(probe.find(ExStates.dockWindows[0]?.contentItem, item => item.elevation !== undefined && item.bordered !== undefined));
        }
        // Which menu is open: the part of the status block it is for, the
        // dock's own, or none.
        function open(): string {
            const popup = ExStates.openPopup;
            if (!popup || !popup.open)
                return "";
            if (popup.kind !== undefined)
                return popup.kind;
            return popup.workspaceId !== undefined ? "dock" : "other";
        }
        function close(): void {
            for (const dock of ExStates.dockWindows)
                dock.closePopups(null);
        }
        // The page quick settings shows, while it is the one open.
        function page(): string {
            const popup = ExStates.openPopup;
            return popup?.open && popup.page !== undefined ? popup.page : "";
        }
        // Pressed as a click would, inside the open popup, which is a window
        // of its own: the arrow after the volume, an entry of a menu by its text.
        function pressArrow(): bool {
            const arrow = probe.find(ExStates.openPopup?.contentItem, item => item.glyph === "chevron_right" && item.kind === "flat" && item.visible);
            arrow?.clicked();
            return arrow !== null;
        }
        function pressGlyph(glyph: string): bool {
            const button = probe.find(ExStates.openPopup?.contentItem, item => item.glyph === glyph && item.kind !== undefined && item.visible);
            button?.clicked();
            return button !== null;
        }
        // The button inside a tile of the tile editor, by the tile's key.
        function pressTileButton(key: string): bool {
            const slot = probe.find(ExStates.openPopup?.contentItem, item => item.modelData === key && item.lifted !== undefined);
            const button = probe.find(slot, item => item !== slot && item.implicitWidth === 28 && item.checkable !== undefined);
            button?.clicked();
            return button !== null;
        }
        // Where a tile of the editor stands within it.
        function tileAt(key: string): string {
            const slot = probe.find(ExStates.openPopup?.contentItem, item => item.modelData === key && item.lifted !== undefined);
            return slot ? JSON.stringify({ x: Math.round(slot.x), y: Math.round(slot.y), shown: slot.shown }) : "";
        }
        function pinned(): string {
            return JSON.stringify(ExQuickTiles.pinned);
        }
        function pressEntry(text: string): bool {
            const entry = probe.find(ExStates.openPopup?.contentItem, item => item.text === Translation.tr(text) && item.iconRoom !== undefined);
            entry?.clicked();
            return entry !== null;
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


def dock_layer(bench) -> dict:
    for data in json.loads(bench.hyprctl("layers", "-j")).values():
        for layers in data["levels"].values():
            for layer in layers:
                if layer["namespace"] == "quickshell:dock":
                    return layer
    raise AssertionError("no dock layer")


def part(bench, shell, name) -> dict:
    """Where a part of the dock is on the screen. The dock places its items as
    if its window met the screen's edge, and the bench's reserved strip puts
    the window above that."""
    r = json.loads(wait_until(lambda: shell.call("statusMenuProbe", name), what=f"the {name} on the dock"))
    layer = dock_layer(bench)
    r["y"] += layer["y"] + layer["h"] - 1080
    return r


def centre(bench, shell, name) -> tuple[int, int]:
    r = part(bench, shell, name)
    return r["x"] + r["width"] // 2, r["y"] + r["height"] // 2


def right_click(desk, x, y):
    pointer = desk.pointer()
    pointer.move(x - 20, y)
    pointer.move(x, y)
    pointer.click(x, y, button="right")


def test_the_clock_has_its_own_menu(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "clock"))
    assert wait_until(lambda: dock.call("statusMenuProbe", "open"), what="a menu to open") == "clock"


def test_the_sound_icon_has_its_own_menu(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "volume"))
    assert wait_until(lambda: dock.call("statusMenuProbe", "open"), what="a menu to open") == "volume"


def test_the_empty_dock_still_has_the_dock_menu(bench, desk, dock):
    plate = part(bench, dock, "plate")
    # A quarter of the way along, clear of the applications in the middle and
    # the status block at the end.
    right_click(desk, plate["x"] + plate["width"] // 4, plate["y"] + plate["height"] // 2)
    assert wait_until(lambda: dock.call("statusMenuProbe", "open"), what="a menu to open") == "dock"


def test_the_arrow_after_the_volume_opens_the_sound_page(dock):
    dock.call("dock", "quickSettings")
    wait_until(lambda: dock.call("statusMenuProbe", "open") == "other", what="quick settings to open")
    assert dock.call("statusMenuProbe", "pressArrow") == "true"
    wait_until(lambda: dock.call("statusMenuProbe", "page") == "sound", what="the sound page")


def test_the_mixer_in_the_sound_menu_opens_the_sound_page(bench, desk, dock):
    right_click(desk, *centre(bench, dock, "volume"))
    wait_until(lambda: dock.call("statusMenuProbe", "open") == "volume", what="the sound menu")
    assert dock.call("statusMenuProbe", "pressEntry", "Volume mixer") == "true"
    wait_until(lambda: dock.call("statusMenuProbe", "page") == "sound", what="quick settings on the sound page")
