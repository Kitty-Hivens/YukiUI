"""The settings pages' number stepper.

Told on at every step, each step rewrote a config file: the compositor read
its whole config again, or an idle daemon restarted, once per step, and steps
made while a write settled were dropped. It now tells on once the stepping
stops, and falls back on the value when the change is refused.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchSettingsNumberProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.settings

// Written by tests/blueberry/test_settings_number.py for a test run, and removed after it.
ShellRoot {
    id: probe

    property real value: 10
    property bool refuse: false
    property var told: []

    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 80
        SettingsNumber {
            id: number
            from: 0
            to: 100
            value: probe.value
            onEdited: value => {
                probe.told = [...probe.told, value];
                if (!probe.refuse)
                    probe.value = value;
            }
        }
    }

    IpcHandler {
        target: "numberProbe"
        function step(times: int): void {
            for (let i = 0; i < times; i++)
                number.step(1);
        }
        function refuse(on: bool): void {
            probe.refuse = on;
        }
        function state(): string {
            return JSON.stringify({ told: probe.told, shown: number.shown, value: probe.value });
        }
    }
}
"""


@pytest.fixture
def number(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("numberProbe", "state"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("numberProbe", "state"))


def test_steps_are_told_once_they_stop(number):
    number.call("numberProbe", "step", "5")
    assert state(number)["shown"] == 15
    wait_until(lambda: state(number)["told"], timeout=3, what="the value to be told")
    time.sleep(0.8)
    assert state(number)["told"] == [15]
    assert state(number)["value"] == 15


def test_a_refused_change_goes_back_to_the_value(number):
    number.call("numberProbe", "refuse", "true")
    number.call("numberProbe", "step", "3")
    wait_until(lambda: state(number)["told"] == [13], timeout=3, what="the value to be told")
    wait_until(lambda: state(number)["shown"] == 10, timeout=4, what="the shown number to go back")
