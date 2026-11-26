"""Super+J puts the dock away until it is pressed again, as ii's bar.

The dock goes past the edge and gives its room to the windows, a maximised one
included, and the edge does not bring it back as it does a dock that hides on
its own.
"""

import json
import time

import pytest

from bench.bench import HEIGHT, SHELL, WIDTH, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockPutAwayProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry
import qs.blueberry.dock
import qs.blueberry.windows

// Written by tests/blueberry/test_dock_put_away.py for a test run, and removed after it.
ShellRoot {
    ExDock {
        id: dock
    }
    ExPlacement {
        id: placement
    }
    IpcHandler {
        target: "putAwayProbe"
        function ready(): bool {
            return Config.ready && dock.docks.length > 0;
        }
        function setUp(): void {
            Config.options.blueberry.dock.autoHide = false;
            Config.options.blueberry.dock.edge = "bottom";
        }
        function hidden(): real {
            return dock.docks[0]?.hidden ?? -1;
        }
        function maximize(address: string): void {
            placement.maximize(address);
        }
    }
}
"""


@pytest.fixture
def dock(desk):
    config = desk.bench.config_home / "illogical-impulse/config.json"
    before = config.read_bytes() if config.exists() else None
    shell = Shell(desk.bench, probe=PROBE, source=SOURCE, ready=("putAwayProbe", "ready"), own_bus=True)
    try:
        shell.start()
        wait_until(lambda: shell.call("putAwayProbe", "ready") == "true", what="the dock")
        shell.call("putAwayProbe", "setUp")
        desk.bench.eval('hl.bind("SUPER + J", hl.dsp.global("quickshell:barToggle"), { description = "Shell: Toggle bar" })')
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        if before is None:
            config.unlink(missing_ok=True)
        else:
            config.write_bytes(before)


def reserved_bottom(desk) -> int:
    return desk.bench.monitors()[0]["reserved"][3]


def press(desk):
    kb = desk.keyboard
    kb.type(*kb.hold("Super_L", "logo"), *kb.tap("j"), *kb.let_go("Super_L", "logo"))


def test_super_j_puts_the_dock_away_and_brings_it_back(dock, desk):
    with_dock = wait_until(lambda: reserved_bottom(desk) if dock.call("putAwayProbe", "hidden") == "0" else None, what="the dock in place")
    press(desk)
    wait_until(lambda: dock.call("bar", "isOpen") == "false", what="the dock put away")
    wait_until(lambda: float(dock.call("putAwayProbe", "hidden")) == 1, what="the dock out of sight")
    away = wait_until(lambda: (lambda r: r if r < with_dock else None)(reserved_bottom(desk)), what="its room given back")
    # The edge does not bring it back.
    pointer = desk.pointer()
    pointer.glide(WIDTH // 2, HEIGHT - 1)
    time.sleep(1.0)
    assert float(dock.call("putAwayProbe", "hidden")) == 1
    press(desk)
    wait_until(lambda: float(dock.call("putAwayProbe", "hidden")) == 0, what="the dock back")
    wait_until(lambda: reserved_bottom(desk) == with_dock, what="its room taken again")
    assert away < with_dock


def test_a_maximised_window_takes_the_room_and_gives_it_back(dock, desk):
    window = desk.wayland()
    dock.call("putAwayProbe", "maximize", window.address)
    tall = wait_until(lambda: (lambda c: c["size"][1] if "maximized" in c["tags"] else None)(window.client()), what="maximised")
    dock.call("bar", "close")
    wait_until(lambda: window.client()["size"][1] > tall, what="the window to take the dock's room")
    dock.call("bar", "open")
    wait_until(lambda: window.client()["size"][1] == tall, what="the window to give it back")
