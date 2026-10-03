"""The display service: applying a layout, and taking it back.

The settings page lets go of its draft once the service is back at rest with
nothing pending. The service went back to rest first and dropped the change
after, so a change taken back stayed on the page as unapplied, one click away
from being applied again.
"""

import json

import pytest

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDisplaysProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_displays.py for a test run, and removed after it.
ShellRoot {
    id: probe

    // Every arrival at rest, and whether a change was still pending then.
    property var rests: []
    Connections {
        target: Displays
        function onStateChanged() {
            if (Displays.state === Displays.stateIdle)
                probe.rests = [...probe.rests, Displays.pendingPlan === null];
        }
    }

    IpcHandler {
        target: "displaysProbe"
        function ready(): string {
            return Displays.outputs.length > 0 ? "yes" : "";
        }
        function state(): string {
            return Displays.state;
        }
        function rests(): string {
            return JSON.stringify(probe.rests);
        }
        function applyScale(scale: real): bool {
            return Displays.apply(Displays.currentPlan().map(entry => Object.assign({}, entry, { scale: scale })));
        }
        function revert(): void {
            Displays.revert();
        }
    }
}
"""


@pytest.fixture
def displays(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("displaysProbe", "ready"))
    try:
        shell.start()
        wait_until(lambda: shell.call("displaysProbe", "ready") == "yes", what="the outputs to be read")
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval(f'hl.monitor({{ output = "{OUTPUT}", scale = 1 }})')


def test_a_change_taken_back_is_gone_when_the_service_is_at_rest(bench, displays):
    assert displays.call("displaysProbe", "applyScale", "2") == "true"
    wait_until(lambda: displays.call("displaysProbe", "state") == "confirming", timeout=10, what="the change to wait for confirmation")
    displays.call("displaysProbe", "revert")
    wait_until(lambda: displays.call("displaysProbe", "state") == "idle", timeout=10, what="the change to be taken back")
    assert json.loads(displays.call("displaysProbe", "rests"))[-1] is True
    wait_until(lambda: bench.monitors()[0]["scale"] == 1, what="the scale to come back")
