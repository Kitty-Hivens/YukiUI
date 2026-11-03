"""Icons on the desktop, over a desktop folder made for the test.

Copying, cutting and pasting go through the bench's own clipboard, with the
helper built for the run.

A file coming into the desktop folder rebuilds the icons from the first one
whose row moved. The icon being dragged was among them, its release never
arrived, and the drag stayed up: the next plain click on any icon dropped it,
moving what had been dragged into the folder it was last over.
"""

import json
import subprocess
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import Keyboard, Pointer

PROBE = SHELL / "benchDesktopProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.blueberry.desktop

// Written by tests/blueberry/test_desktop_icons.py for a test run, and removed after it.
ShellRoot {
    PanelWindow {
        id: window
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Background
        exclusionMode: ExclusionMode.Ignore
        // As the background asks for the keys.
        WlrLayershell.keyboardFocus: !icons.wantsKeys ? WlrKeyboardFocus.None
            : icons.seizing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        ExDesktopIcons {
            id: icons
            anchors.fill: parent
            screenModel: window.screen
        }
    }
    IpcHandler {
        target: "desktopProbe"
        function ready(): string {
            return "yes";
        }
        // "New" in the desktop's menu, right clicked at that point.
        function create(folder: bool, x: real, y: real): void {
            icons.create(folder, Qt.point(x, y));
        }
        function renaming(): string {
            return icons.renaming;
        }
        function templates(): string {
            return JSON.stringify(icons.templates);
        }
        // "New" from the template of that name, right clicked at that point.
        function createFrom(name: string, x: real, y: real): bool {
            const template = icons.templates.find(candidate => icons.templateName(candidate) === name);
            if (template)
                icons.createFrom(template, Qt.point(x, y));
            return template !== undefined;
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
    # And a templates folder, as Nautilus keeps its templates.
    templates = tmp_path / "Templates"
    templates.mkdir()
    (templates / "Report.md").write_text("# Report\n")
    user_dirs = bench.config_home / "user-dirs.dirs"
    user_dirs.write_text(f'XDG_DESKTOP_DIR="{folder}"\nXDG_TEMPLATES_DIR="{templates}"\n')
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


def ctrl(key: str) -> list[str]:
    return [*Keyboard.hold("Control_L", "ctrl"), *Keyboard.tap(key), *Keyboard.let_go("Control_L", "ctrl")]


def clipboard(bench, kind: str) -> str:
    return subprocess.run(["wl-paste", "--no-newline", "--type", kind], env=bench.environment(),
                          capture_output=True, text=True).stdout


def test_files_are_copied_and_pasted_as_the_file_manager_does(desktop, bench):
    folder, shell, pointer = desktop
    subprocess.run(["wl-copy", "--clear"], env=bench.environment(), check=True)
    # A click on the desktop gives it the keys, then all of it is picked.
    pointer.click(*cell_centre(1))
    time.sleep(0.3)
    keyboard = Keyboard(bench)
    keyboard.type(*ctrl("a"))
    keyboard.type(*ctrl("c"))
    listing = wait_until(lambda: clipboard(bench, "x-special/gnome-copied-files"), what="the files on the clipboard")
    lines = listing.split("\n")
    assert lines[0] == "copy"
    assert sorted(lines[1:]) == sorted(f"file://{folder / name}" for name in ("a.txt", "b.txt", "box"))
    keyboard.type(*ctrl("v"))
    wait_until(lambda: (folder / "a (copy).txt").exists() and (folder / "box (copy)").is_dir(), what="the copies")
    assert (folder / "b (copy).txt").read_text() == "b.txt"
    assert not shell.errors()


def test_files_cut_elsewhere_are_moved_in(desktop, bench, tmp_path):
    folder, shell, pointer = desktop
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    for name in ("one file.txt", "two.txt"):
        (elsewhere / name).write_text(name)
    subprocess.run(["bash", str(SHELL / "scripts/clipboard/offer.sh"), "--cut", str(elsewhere / "one file.txt"),
                    str(elsewhere / "two.txt")], env=bench.environment(), check=True)
    assert clipboard(bench, "x-special/gnome-copied-files").startswith("cut\nfile://")
    # On the empty desktop, past the icons.
    pointer.click(600, 400)
    time.sleep(0.3)
    Keyboard(bench).type(*ctrl("v"))
    wait_until(lambda: (folder / "one file.txt").exists() and (folder / "two.txt").exists(), what="the files to be moved in")
    assert list(elsewhere.iterdir()) == []
    assert not shell.errors()


def type_text(keyboard: Keyboard, text: str):
    steps = []
    for char in text:
        steps += Keyboard.tap({" ": "space", ".": "period"}.get(char, char))
    keyboard.type(*steps)


def test_something_new_is_made_where_clicked_and_named_there(desktop, bench):
    folder, shell, pointer = desktop
    # Right clicked on the third column, second row, clear of the icons.
    x, y = 8 + 2 * 84 + 42, 8 + 96 + 48
    pointer.click(x, y, button="right")
    shell.call("desktopProbe", "create", "true", str(x), str(y))
    wait_until(lambda: (folder / "New folder").is_dir(), what="the new folder")
    wait_until(lambda: shell.call("desktopProbe", "renaming") == "New folder", what="its name to be typed")
    time.sleep(0.3)
    keyboard = Keyboard(bench)
    type_text(keyboard, "projects")
    keyboard.type(*Keyboard.tap("Return"))
    wait_until(lambda: (folder / "projects").is_dir(), what="the folder to take the name typed")
    assert not (folder / "New folder").exists()
    places = wait_until(lambda: "projects" in kept_cells(bench) and kept_cells(bench), timeout=4, what="its cell to be kept")
    assert places["projects"] == [2, 1], "not made where the desktop was clicked"
    assert not shell.errors()


def test_f2_names_a_file_and_keeps_its_extension_and_escape_keeps_its_name(desktop, bench):
    folder, shell, pointer = desktop
    pointer.click(*cell_centre(1))
    time.sleep(0.3)
    keyboard = Keyboard(bench)
    keyboard.type(*Keyboard.tap("F2"))
    wait_until(lambda: shell.call("desktopProbe", "renaming") == "a.txt", what="the name to be typed")
    time.sleep(0.2)
    # The part before the extension is picked, so typing replaces only it.
    type_text(keyboard, "notes")
    keyboard.type(*Keyboard.tap("Return"))
    wait_until(lambda: (folder / "notes.txt").exists(), what="the file to take the name typed")

    pointer.click(*cell_centre(1))
    time.sleep(0.3)
    keyboard.type(*Keyboard.tap("F2"))
    wait_until(lambda: shell.call("desktopProbe", "renaming") == "notes.txt", what="the name to be typed again")
    time.sleep(0.2)
    type_text(keyboard, "other")
    keyboard.type(*Keyboard.tap("Escape"))
    wait_until(lambda: shell.call("desktopProbe", "renaming") == "", what="the change to be left")
    time.sleep(0.5)
    assert (folder / "notes.txt").exists() and not (folder / "other.txt").exists()
    assert not shell.errors()


def test_something_new_is_made_from_a_template_and_named_there(desktop, bench):
    folder, shell, pointer = desktop
    x, y = 8 + 2 * 84 + 42, 8 + 48
    wait_until(lambda: shell.call("desktopProbe", "createFrom", "Report", str(x), str(y)) == "true",
               what="the template to be listed")
    wait_until(lambda: (folder / "Report.md").exists(), what="the copy of the template")
    assert (folder / "Report.md").read_text() == "# Report\n"
    wait_until(lambda: shell.call("desktopProbe", "renaming") == "Report.md", what="its name to be typed")
    assert not shell.errors()
