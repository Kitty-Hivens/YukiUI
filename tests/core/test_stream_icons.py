"""The icon shown for a program playing sound, when no desktop entry names one.

A game run through Proton plays sound as its .exe, which no desktop entry and
no theme icon is named for, and the sound views showed the icon for a missing
one while the dock showed the game's. The stream is matched to the window its
process shows, and that window's icon is found as the dock finds it.

The streams here are stand-ins, an object carrying what PipeWire would say of
one: its process and its name. Nothing plays.
"""

import os

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import IconWindow

PROBE = SHELL / "benchStreamIconsProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_stream_icons.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "streamIconsProbe"
        function ready(): string {
            return "yes";
        }
        function iconFor(pid: string, name: string): string {
            return StreamApps.iconSourceFor({ properties: { "application.process.id": pid, "node.name": name } });
        }
    }
}
"""


@pytest.fixture
def probe(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("streamIconsProbe", "ready"))
    shell.start()
    yield shell
    shell.stop()
    shell.remove_probe()


def icon_window(desk, stem: str, **kwargs) -> IconWindow:
    window = IconWindow(desk.bench, desk.name(stem), **kwargs)
    desk.windows.append(window)
    return window


def pid_of(desk, window) -> str:
    return str(wait_until(lambda: next((c["pid"] for c in desk.bench.clients() if c["class"] == window.wm_class), 0),
                          what=f"{window.wm_class} to have a window"))


def test_a_stream_takes_the_picture_its_window_gave(desk, probe):
    window = icon_window(desk, "game", colour="0000ff", size=64)
    pid = pid_of(desk, window)
    source = wait_until(lambda: (s := probe.call("streamIconsProbe", "iconFor", pid, "Game.exe")).startswith("file://") and s,
                        what="the window's picture")
    assert "yuki-window-icons" in source


def test_a_stream_takes_the_theme_icon_its_window_named(desk, probe):
    window = icon_window(desk, "named", name="utilities-terminal")
    pid = pid_of(desk, window)
    wait_until(lambda: "utilities-terminal" in probe.call("streamIconsProbe", "iconFor", pid, "Named.exe"),
               what="the icon the window named")


def test_a_stream_with_no_window_is_guessed_as_before(desk, probe):
    # This process shows no window on the bench.
    source = probe.call("streamIconsProbe", "iconFor", str(os.getpid()), "Nothing_Here.exe")
    assert source, "no icon at all"
    assert "yuki-window-icons" not in source
