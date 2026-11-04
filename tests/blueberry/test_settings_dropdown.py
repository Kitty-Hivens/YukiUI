"""A choice in a list of the settings can be read whole.

The list stayed as wide as its box whatever it held, and a sound card's
profiles all read "Digital Stereo (H...": seven of them, told apart by nothing.
"""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchSettingsDropdownProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.settings

// Written by tests/blueberry/test_settings_dropdown.py for a test run, and removed after it.
ShellRoot {
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        title: "dropdown probe"
        SettingsDropdown {
            id: long
            x: 600
            y: 40
            width: 200
            currentIndex: 0
            model: ["Off", "Digital Stereo (HDMI) Output + Analog Stereo Input", "Digital Surround 7.1 (HDMI 2) Output + Analog Stereo Input"]
        }
        SettingsDropdown {
            id: short
            x: 600
            y: 100
            width: 200
            currentIndex: 0
            model: ["Off", "On"]
        }
    }
    IpcHandler {
        target: "dropdownProbe"
        function ready(): bool {
            return true;
        }
        function open(which: string): string {
            const box = which === "long" ? long : short;
            box.list.open();
            return JSON.stringify({ box: box.width, list: box.list.width, x: box.list.x });
        }
        function close(which: string): void {
            (which === "long" ? long : short).list.close();
        }
    }
}
"""


@pytest.fixture
def dropdown(bench, desk):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dropdownProbe", "ready"))
    try:
        shell.start()
        wait_until(lambda: any(c["title"] == "dropdown probe" for c in bench.clients()), what="the window")
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def test_a_list_of_long_choices_is_as_wide_as_they_are(dropdown):
    opened = json.loads(dropdown.call("dropdownProbe", "open", "long"))
    assert opened["list"] > 380, opened
    # Grown towards the page, its far edge on the box's.
    assert opened["x"] == opened["box"] - opened["list"]


def test_a_list_of_short_choices_stays_as_wide_as_its_box(dropdown):
    opened = json.loads(dropdown.call("dropdownProbe", "open", "short"))
    assert opened["list"] == opened["box"]
