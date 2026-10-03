"""Icons on the desktop, over a desktop folder made for the test.

A file coming into the desktop folder rebuilds the icons from the first one
whose row moved. The icon being dragged was among them, its release never
arrived, and the drag stayed up: the next plain click on any icon dropped it,
moving what had been dragged into the folder it was last over.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import Pointer

PROBE = SHELL / "benchDesktopProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.experimental.desktop

// Written by tests/experimental/test_desktop_icons.py for a test run, and removed after it.
ShellRoot {
    PanelWindow {
        id: window
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Background
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        ExDesktopIcons {
            anchors.fill: parent
            screenModel: window.screen
        }
    }
    IpcHandler {
        target: "desktopProbe"
        function ready(): string {
            return "yes";
        }
    }
}
"""

# Medium icons on a dock at the bottom: cells of 84 by 96 from 8, 8, filled
# down the first column, folders first.
def cell_centre(row: int) -> tuple[int, int]:
    return 8 + 42, 8 + row * 96 + 48


@pytest.fixture
def desktop(bench, tmp_path):
    folder = tmp_path / "Desktop"
    (folder / "box").mkdir(parents=True)
    for name in ("a.txt", "b.txt"):
        (folder / name).write_text(name)
    user_dirs = bench.config_home / "user-dirs.dirs"
    user_dirs.write_text(f'XDG_DESKTOP_DIR="{folder}"\n')
    # The cells kept are by name, and an earlier test's are not this one's.
    for kept in bench.state_home.rglob("desktop-icons.json"):
        kept.unlink()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("desktopProbe", "ready"))
    pointer = Pointer(bench)
    try:
        shell.start()
        # The folder is listed on a thread of its own.
        time.sleep(1.5)
        yield folder, shell, pointer
    finally:
        pointer.close()
        shell.stop()
        shell.remove_probe()
        user_dirs.unlink(missing_ok=True)


def test_drag_cut_short_by_a_new_file_drops_nothing_later(desktop):
    folder, shell, pointer = desktop
    # a.txt carried over the folder, held there.
    pointer.move(*cell_centre(1))
    pointer.press()
    pointer.glide(*cell_centre(0))
    time.sleep(0.3)
    # A file that sorts before it comes in, and the icons are rebuilt from it.
    (folder / "0.txt").write_text("new")
    time.sleep(1.0)
    pointer.release()
    time.sleep(0.3)
    # A plain click on another icon, the pointer still between press and
    # release as most clicks are. One that moves a pixel reads the drop
    # again from where it is and hid the fault.
    pointer.move(*cell_centre(2))
    time.sleep(0.1)
    pointer.press()
    pointer.release()
    time.sleep(1.0)
    assert sorted(p.name for p in folder.iterdir()) == ["0.txt", "a.txt", "b.txt", "box"]
    assert list((folder / "box").iterdir()) == [], "a click moved files into the folder a drag had ended over"
    assert not shell.errors()


def kept_cells(bench) -> dict:
    files = list(bench.state_home.rglob("desktop-icons.json"))
    return json.loads(files[0].read_text())["places"] if files else {}


def test_a_renamed_file_keeps_its_cell(desktop, bench):
    # Renamed, a file keeps the cell it had rather than going to the first
    # free one, the way Windows keeps it.
    folder, shell, _ = desktop
    # The cells are written a moment after they are given.
    wait_until(lambda: "a.txt" in kept_cells(bench), timeout=4, what="the cells to be kept")
    (folder / "a.txt").rename(folder / "z.txt")
    places = wait_until(lambda: "z.txt" in kept_cells(bench) and kept_cells(bench), timeout=4, what="the new name to be kept")
    assert places["z.txt"] == [0, 1]
    assert "a.txt" not in places
    assert not shell.errors()
