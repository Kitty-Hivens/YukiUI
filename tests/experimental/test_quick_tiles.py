"""Arranging the tiles of quick settings: dragged into order, unpinned and added.

The tiles are placed by hand while they are arranged: a layout fed a new order
made every tile anew as the drag went, the dragged one and its drag with it.
The desktop is plain red so the panel is easy to find in a capture.
"""

import json
import subprocess
import time

import pytest
from PIL import Image

from bench.bench import HEIGHT, OUTPUT, SHELL, WIDTH, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchQuickTilesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.experimental
import qs.experimental.dock
import qs.experimental.looks

// Written by tests/experimental/test_quick_tiles.py for a test run, and removed after it.
ShellRoot {
    // At the bottom, wherever an earlier test left it: the bench's settings
    // outlive one test.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.experimental.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.experimental.dock.edge = "bottom";
    }
    ExDock {}
    IpcHandler {
        target: "tilesProbe"
        function edit(): void {
            ExStates.openPopup.startEditing();
        }
        function editing(): bool {
            return ExStates.openPopup?.editing ?? false;
        }
        function padding(): real {
            return ExStates.openPopup.padding;
        }
        // How far below the top of the panel's content the tiles start: a
        // line saying what to do stands over them.
        function tilesTop(): real {
            const find = (item, has) => {
                if (!item)
                    return null;
                if (has(item))
                    return item;
                for (const child of item.children ?? []) {
                    const found = find(child, has);
                    if (found)
                        return found;
                }
                return null;
            };
            const editor = find(ExStates.openPopup?.contentItem, item => item.spareTop !== undefined);
            return editor ? editor.mapToItem(editor.parent.parent, 0, 0).y : -1;
        }
        function cell(): string {
            return JSON.stringify({ width: (400 - ExLooks.spacing.s) / 2, height: ExLooks.sizes.tileHeight, gap: ExLooks.spacing.s });
        }
        function pinned(): string {
            return JSON.stringify(ExQuickTiles.pinned);
        }
        function unpinned(): string {
            return JSON.stringify(ExQuickTiles.unpinned);
        }
        function saved(): string {
            return JSON.stringify([...Config.options.experimental.quickSettings.tiles]);
        }
    }
}
"""


@pytest.fixture
def dock(bench):
    bench.eval('hl.config({ misc = { force_default_wallpaper = 0, background_color = "rgb(ff0000)" } })')
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dock", "activate", "99"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval('hl.config({ misc = { force_default_wallpaper = -1, background_color = "rgb(111111)" } })')


def panel_corner(path) -> tuple[int, int]:
    """The top left corner of quick settings in a capture: the panel stands in
    the lower right corner, above the dock, on the red desktop."""
    image = Image.open(path).convert("RGB")
    red = lambda p: p[0] > 200 and p[1] < 60 and p[2] < 60
    column = WIDTH - 100
    # Below the compositor's own warning along the top right.
    top = next(y for y in range(80, HEIGHT) if not red(image.getpixel((column, y))))
    row = top + 40
    left = next(x for x in range(WIDTH // 2, WIDTH) if not red(image.getpixel((x, row))))
    return left, top


def json_call(shell, function):
    return json.loads(shell.call("tilesProbe", function))


def test_tiles_are_dragged_into_order_unpinned_and_kept(bench, desk, dock, tmp_path):
    dock.call("dock", "quickSettings")
    time.sleep(1.0)
    dock.call("tilesProbe", "edit")
    wait_until(lambda: dock.call("tilesProbe", "editing") == "true", what="quick settings to be arranged")
    time.sleep(1.0)
    shot = tmp_path / "editing.png"
    subprocess.run(["grim", "-o", OUTPUT, str(shot)], env=bench.environment(), check=True)
    left, top = panel_corner(shot)
    padding = float(dock.call("tilesProbe", "padding"))
    tiles_top = top + padding + float(dock.call("tilesProbe", "tilesTop"))
    cell = json_call(dock, "cell")

    def centre(index):
        x = left + padding + (index % 2) * (cell["width"] + cell["gap"]) + cell["width"] / 2
        y = tiles_top + (index // 2) * (cell["height"] + cell["gap"]) + cell["height"] / 2
        return round(x), round(y)

    before = json_call(dock, "pinned")
    assert len(before) >= 4, before
    pointer = desk.pointer()
    pointer.move(*centre(0))
    pointer.press()
    x, y = centre(3)
    pointer.glide(x, y)
    time.sleep(0.3)
    pointer.release()
    expected = before[1:4] + [before[0]] + before[4:]
    wait_until(lambda: json_call(dock, "saved")[:len(expected)] == expected, what=f"the order {expected}")

    # The button that takes a tile out stands at the tile's right end.
    button_x = round(left + padding + cell["width"] - 8 - 14)
    button_y = centre(0)[1]
    pointer.glide(button_x, button_y)
    pointer.click(button_x, button_y)
    wait_until(lambda: expected[0] not in json_call(dock, "pinned"), what=f"{expected[0]} to be unpinned")
    assert expected[0] in json_call(dock, "unpinned")
    assert not dock.errors()
