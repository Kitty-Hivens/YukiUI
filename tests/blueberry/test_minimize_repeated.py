"""Clicked again while its picture is in the air, a window is sent off once.

The compositor keeps a window minimised until its picture has flown back out
of the dock, so a second click during the flight, which meant to turn it round,
found it still minimised and sent it off again: the second picture hung over
the window that had already come back. A window in the air is now left to
arrive, and the last thing asked of it is done then.

With an animator that holds each flight until told to let it land, which is
the one thing a real one does on its own.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchMinimizeRepeatedProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/blueberry/test_minimize_repeated.py for a test run, and removed after it.
ShellRoot {
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }
    QtObject {
        id: holder
        property var flights: []
        property var sent: []
        function hold(kind, windows, go, landed) {
            for (const win of windows) {
                holder.sent = [...holder.sent, `${kind} ${win.address}`];
                holder.flights = [...holder.flights, { address: win.address, go: go, landed: landed }];
            }
            // Out of sight at once, as the real one does, and the picture flies on.
            if (kind === "minimize")
                go();
        }
        function minimize(windows, go, landed) {
            holder.hold("minimize", windows, go, landed);
        }
        function restore(windows, go, landed) {
            holder.hold("restore", windows, go, landed);
        }
    }
    Binding {
        target: Minimize
        property: "animator"
        value: holder
    }
    IpcHandler {
        target: "repeatedProbe"
        function ready(): string {
            return HyprlandData.windowList ? "yes" : "";
        }
        function sent(): string {
            return JSON.stringify(holder.sent);
        }
        function busy(address: string): bool {
            return Minimize.busy(address);
        }
        function land(): void {
            const flights = holder.flights;
            holder.flights = [];
            for (const flight of flights) {
                flight.go();
                flight.landed(flight.address);
            }
        }
    }
}
"""


@pytest.fixture
def held(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("repeatedProbe", "ready"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def sent(shell) -> list:
    return json.loads(shell.call("repeatedProbe", "sent"))


def toggle(shell, window, times: int = 1):
    for _ in range(times):
        shell.call("minimize", "toggle", window.address)
        time.sleep(0.15)


def wait_sent(shell, count: int, what: str):
    wait_until(lambda: len(sent(shell)) >= count, what=what)


def test_a_click_during_the_flight_out_does_not_send_it_off_again(desk, held):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    toggle(held, window)
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    held.call("repeatedProbe", "land")
    wait_until(lambda: held.call("repeatedProbe", "busy", window.address) == "false", what="the flight in to end")

    # Coming back, clicked twice more while its picture is in the air: that is
    # back where it was, and it stays as it was first asked.
    toggle(held, window, 3)
    assert [line.split()[0] for line in sent(held)] == ["minimize", "restore"], "a flight was started again"

    held.call("repeatedProbe", "land")
    window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")
    time.sleep(1)
    assert [line.split()[0] for line in sent(held)] == ["minimize", "restore"]


def test_the_last_click_during_a_flight_is_done_when_it_lands(desk, held):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    toggle(held, window)
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")

    # Still in the air going in: one click turns it round, once it is in.
    toggle(held, window)
    assert [line.split()[0] for line in sent(held)] == ["minimize"]
    held.call("repeatedProbe", "land")
    wait_sent(held, 2, "the window to be sent back")
    assert [line.split()[0] for line in sent(held)] == ["minimize", "restore"]
    held.call("repeatedProbe", "land")
    window.wait(lambda c: c["workspace"].get("id") == workspace, "brought back")
    wait_until(lambda: held.call("repeatedProbe", "busy", window.address) == "false", what="the flight out to end")


def test_an_animator_that_never_reports_does_not_hold_a_window_for_good(desk, held):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    toggle(held, window)
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
    wait_until(lambda: held.call("repeatedProbe", "busy", window.address) == "false", timeout=8, what="the window to be let go of")
    toggle(held, window)
    wait_sent(held, 2, "the window to be brought back")
