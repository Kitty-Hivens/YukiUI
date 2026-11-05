"""A switch for what the system decides shows what was asked at once, and goes
back only if the system never comes round.

Bound to the system alone it sprang back under the finger and looked refused
until the radio had answered.
"""

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchSystemSwitchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.looks

// Written by tests/blueberry/test_system_switch.py for a test run, and removed after it.
ShellRoot {
    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 100
        title: "switch probe"
        ExSystemSwitch {
            id: sw
            patience: 700
            on: false
            onSwitched: wanted => probe.lastAsked = wanted
        }
    }
    QtObject {
        id: probe
        property var lastAsked: null
    }
    IpcHandler {
        target: "switchProbe"
        function ready(): bool {
            return true;
        }
        function press(): void {
            sw.clicked();
        }
        function answer(on: bool): void {
            sw.on = on;
        }
        function shown(): bool {
            return sw.checked;
        }
        function asked(): string {
            return String(probe.lastAsked);
        }
    }
}
"""


@pytest.fixture
def switch(bench, desk):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("switchProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def test_it_shows_what_was_asked_and_keeps_to_the_answer(switch):
    assert switch.call("switchProbe", "shown") == "false"
    switch.call("switchProbe", "press")
    assert switch.call("switchProbe", "shown") == "true", "it sprang back under the finger"
    assert switch.call("switchProbe", "asked") == "true"
    switch.call("switchProbe", "answer", "true")
    assert switch.call("switchProbe", "shown") == "true"
    # And it follows the system afterwards, whoever changed it.
    switch.call("switchProbe", "answer", "false")
    assert switch.call("switchProbe", "shown") == "false"


def test_it_goes_back_if_the_system_never_answers(switch):
    switch.call("switchProbe", "press")
    assert switch.call("switchProbe", "shown") == "true"
    wait_until(lambda: switch.call("switchProbe", "shown") == "false", what="it to go back")
