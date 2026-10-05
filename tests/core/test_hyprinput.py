"""Input settings as the shared service reads them from the compositor.

The compositor reports a switch as "bool", and the service read every switch
as a number, so each one showed off whatever was set.
"""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchHyprInputProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_hyprinput.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "inputProbe"
        function refresh(): void {
            HyprInput.ready = false;
            HyprInput.refresh();
        }
        function state(): string {
            return JSON.stringify({
                ready: HyprInput.ready,
                naturalScroll: HyprInput.touchpadNaturalScroll,
                tapToClick: HyprInput.touchpadTapToClick,
                tapAndDrag: HyprInput.touchpadTapAndDrag,
                disableWhileTyping: HyprInput.touchpadDisableWhileTyping,
                numlock: HyprInput.numlock,
                leftHanded: HyprInput.leftHanded
            });
        }
    }
}
"""


@pytest.fixture
def hyprinput(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("inputProbe", "state"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.reload()


def read(shell) -> dict:
    shell.call("inputProbe", "refresh")
    return wait_until(lambda: (lambda s: s if s["ready"] else None)(json.loads(shell.call("inputProbe", "state"))),
                      what="the service to read the compositor")


@pytest.mark.parametrize("on", [True, False])
def test_switches_read_as_set(bench, hyprinput, on):
    lua = "true" if on else "false"
    bench.eval(f"hl.config({{ input = {{ numlock_by_default = {lua}, left_handed = {lua}, touchpad = {{ natural_scroll = {lua}, "
               f"tap_to_click = {lua}, tap_and_drag = {lua}, disable_while_typing = {lua} }} }} }})")
    state = read(hyprinput)
    for key in ("naturalScroll", "tapToClick", "tapAndDrag", "disableWhileTyping", "numlock", "leftHanded"):
        assert state[key] is on, f"{key} read as {state[key]}"
