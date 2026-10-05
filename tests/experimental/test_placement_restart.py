"""Placed windows across a restart of the shell, with a dock that reserves room.

The dock goes with the shell and comes back a moment after it, and the shell
read the work area as it started, without the dock. A maximised window was
fitted to the whole screen and went on under the dock, and a snapped one no
longer stood on a half of that area and was let go of.

A stand in for the dock, a layer reserving room at the bottom on top of what
the bench reserves, is stopped with the shell and started after it.
"""

import time

import pytest

from bench.bench import HEIGHT, RESERVED_BOTTOM, SHELL, WIDTH, wait_until
from bench.shell import Shell

DOCK = SHELL / "benchDockStandInProbe.qml"
DOCK_HEIGHT = 48
SOURCE = f"""import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Written by tests/experimental/test_placement_restart.py for a test run, and removed after it.
ShellRoot {{
    PanelWindow {{
        anchors {{
            bottom: true
            left: true
            right: true
        }}
        implicitHeight: {DOCK_HEIGHT}
        exclusiveZone: {DOCK_HEIGHT}
        color: "transparent"
        WlrLayershell.namespace: "quickshell:benchdock"
    }}
    IpcHandler {{
        target: "dockStandIn"
        function ready(): string {{
            return "yes";
        }}
    }}
}}
"""

AREA = (0, 0, WIDTH, HEIGHT - RESERVED_BOTTOM - DOCK_HEIGHT)


@pytest.fixture
def dock(desk):
    dock = Shell(desk.bench, probe=DOCK, source=SOURCE, ready=("dockStandIn", "ready"))
    try:
        yield dock
    finally:
        dock.stop()
        dock.remove_probe()


def reserved_bottom(bench) -> int:
    return bench.monitors()[0]["reserved"][3]


def start(dock, bench):
    dock.start()
    wait_until(lambda: reserved_bottom(bench) == RESERVED_BOTTOM + DOCK_HEIGHT, what="the dock to reserve its room")


def rect(client) -> tuple:
    return (*client["at"], *client["size"])


def test_placed_windows_fit_the_dock_after_a_shell_restart(desk, dock):
    start(dock, desk.bench)
    maximized = desk.wayland()
    snapped = desk.wayland()
    before = snapped.rect
    desk.place(maximized, "maximized")
    desk.place(snapped, "left")
    x, y, w, h = AREA
    maximized.wait(lambda c: rect(c) == AREA, "maximised over the dock")
    snapped.wait(lambda c: rect(c) == (x, y, round(w / 2), h), "snapped above the dock")

    # The dock goes with the shell, and is back a moment after it.
    dock.stop()
    desk.shell.restart()
    time.sleep(0.8)
    start(dock, desk.bench)

    maximized.wait(lambda c: rect(c) == AREA and "maximized" in c["tags"], "maximised over the dock again")
    snapped.wait(lambda c: rect(c) == (x, y, round(w / 2), h) and "snapped" in c["tags"], "snapped above the dock again")
    # Where it stood is known to the new shell too.
    desk.restore(snapped)
    snapped.wait(lambda c: rect(c) == before and not c["tags"], "put back where it stood")
