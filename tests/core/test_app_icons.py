"""The icon the shell shows for a window of an application with no desktop entry.

Minecraft and Steam's games showed a generic icon in the dock. Minecraft's class
was matched to an icon named "minecraft", which no theme here has, and the
dock showed it missing. A game started by Steam has a class of its own that
names nothing installed.

Now a window of a class no entry is named for shows, best first, the icon Steam
installed for the game its process says it is, then the icon the window gave
itself through the window-icons plugin. An application with an entry still
shows the theme's icon for it, an entry found by the class it says it starts
windows under included: Nexira's, named dev.hivens.nexira, was found for its
menu but not for its icon, and its Java window gave the dock Java's own.

Steam's part is played by a data folder of the test's own: a game's icon and
its desktop entry under Steam's names, and the game's id in the window's
environment, as Steam starts a game.
"""

import subprocess

import pytest
from PIL import Image

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import X11Window

PROBE = SHELL / "benchAppIconsProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.waffle.looks

// Written by tests/core/test_app_icons.py for a test run, and removed after it.
ShellRoot {
    // Woken, as the shell wakes them as it starts.
    Component.onCompleted: HyprlandData.windowList
    // Waffle's icon, which takes a name or a picture's url.
    FloatingWindow {
        visible: true
        title: "appIconsProbe"
        color: "black"
        implicitWidth: 64
        implicitHeight: 64
        WAppIcon {
            id: waffleIcon
            iconName: ""
            implicitSize: 48
        }
    }
    IpcHandler {
        target: "appIcons"
        function ready(): string {
            return "yes";
        }
        function iconFor(appClass: string): string {
            return AppSearch.iconFor(appClass);
        }
        function entryName(appClass: string): string {
            return AppSearch.entryFor(appClass)?.name ?? "";
        }
        function iconNameFor(appClass: string): string {
            return AppSearch.iconNameFor(appClass);
        }
        // Shows in Waffle's icon what is chosen for the class.
        function waffleShow(appClass: string): void {
            waffleIcon.iconName = AppSearch.iconNameFor(appClass);
        }
        function steamApp(appClass: string): string {
            return WindowIcons.steamAppOf(appClass);
        }
        function iconExists(name: string): bool {
            return AppSearch.iconExists(name);
        }
    }
}
"""

GAME = "4242"


@pytest.fixture
def shell(bench, tmp_path):
    data = tmp_path / "data"
    icon = data / "icons/hicolor/48x48/apps"
    icon.mkdir(parents=True)
    Image.new("RGBA", (48, 48), (0, 128, 255, 255)).save(icon / f"steam_icon_{GAME}.png")
    applications = data / "applications"
    applications.mkdir()
    (applications / "Bench Game.desktop").write_text(
        f"[Desktop Entry]\nName=Bench Game\nType=Application\nExec=steam steam://rungameid/{GAME}\nIcon=steam_icon_{GAME}\n")
    Image.new("RGBA", (48, 48), (0, 200, 0, 255)).save(icon / "bench_launcher_icon.png")
    (applications / "dev.bench.launcher.desktop").write_text(
        "[Desktop Entry]\nName=Bench Launcher\nType=Application\nExec=true\nIcon=bench_launcher_icon\nStartupWMClass=BenchLauncher\n")
    import os
    dirs = f"{data}:{os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')}"
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("appIcons", "ready"), env={"XDG_DATA_DIRS": dirs})
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


@pytest.fixture
def windows(bench):
    opened = []

    def open_window(*args, **kwargs):
        window = X11Window(bench, *args, **kwargs)
        opened.append(window)
        return window

    yield open_window
    for window in opened:
        try:
            window.close()
        except Exception:
            window.kill()


def waffle_pixel(bench, tmp_path):
    """The middle of Waffle's icon in the probe's window, as drawn on the screen.
    Kirigami's icon says it is valid whatever it shows, so the screen is asked."""
    probe = next(c for c in bench.clients() if c["title"] == "appIconsProbe")
    x, y = probe["at"]
    shot = tmp_path / "waffle-icon.png"
    subprocess.run(["grim", "-g", f"{x},{y} 48x48", str(shot)], env=bench.environment(), check=True)
    return Image.open(shot).convert("RGB").getpixel((24, 24))


def icon(shell, appClass):
    return shell.call("appIcons", "iconFor", appClass)


def test_a_window_with_no_entry_shows_the_icon_it_gave_itself(shell, windows, bench, tmp_path):
    # Away from the probe's window in the middle, which the screen is asked about.
    window = windows("bench.icons.own", x=1400, y=100, width=300, height=200, own=("icon",))
    # Asked as the dock asks, by the class lowercased.
    found = wait_until(lambda: (lambda path: path if "yuki-window-icons" in path else None)(icon(shell, window.wm_class.lower())),
                       what="its own icon")
    assert found.startswith("file://")
    # The same for widgets that take an icon by name, Waffle's, which draws
    # the picture: red, as the window gives it.
    assert shell.call("appIcons", "iconNameFor", window.wm_class.lower()) == found
    shell.call("appIcons", "waffleShow", window.wm_class.lower())
    wait_until(lambda: waffle_pixel(bench, tmp_path) == (255, 0, 0), what="Waffle's icon to draw the window's red picture")


def test_minecraft_shows_its_own_icon_not_a_missing_one(shell, windows):
    window = windows("Minecraft* bench", own=("icon",))
    found = wait_until(lambda: (lambda path: path if "yuki-window-icons" in path else None)(icon(shell, window.wm_class.lower())),
                       what="Minecraft's own icon")
    assert "image-missing" not in found


def test_a_steam_game_shows_its_steam_icon_and_entry(shell, windows):
    window = windows("bench.icons.game", env={"SteamAppId": GAME})
    # Which game it is, from its process, and the icon Steam installed for it.
    wait_until(lambda: shell.call("appIcons", "steamApp", window.wm_class.lower()) == GAME, what="the game's Steam id")
    assert shell.call("appIcons", "iconExists", f"steam_icon_{GAME}") == "true", "the game's icon is not found in the theme"
    found = wait_until(lambda: (lambda path: path if f"steam_icon_{GAME}" in path else None)(icon(shell, window.wm_class.lower())),
                       what="the game's Steam icon")
    assert found
    assert shell.call("appIcons", "entryName", window.wm_class.lower()) == "Bench Game"
    assert shell.call("appIcons", "iconNameFor", window.wm_class.lower()) == f"steam_icon_{GAME}"


def test_an_entry_found_by_its_startup_class_gives_the_icon_not_the_window(shell, windows):
    # Named otherwise than its windows' class, which it declares instead, and
    # the window gives an icon of its own, as Java gives every window its own.
    window = windows("BenchLauncher", own=("icon",))
    wait_until(lambda: shell.call("appIcons", "entryName", "benchlauncher") == "Bench Launcher", what="the entry, by its startup class")
    found = wait_until(lambda: (lambda path: path if "bench_launcher_icon" in path else None)(icon(shell, window.wm_class.lower())),
                       what=f"the entry's icon, last {icon(shell, window.wm_class.lower())}")
    assert "yuki-window-icons" not in found
    assert shell.call("appIcons", "iconNameFor", "benchlauncher") == "bench_launcher_icon"
