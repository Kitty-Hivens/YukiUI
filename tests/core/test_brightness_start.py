"""A shell coming up only reads the backlight, it does not set it.

The brightness started at nought and was animated to the value read from the
backlight, and every frame of that was written back: each shell starting, the
settings window opening, and every bench probe drove the machine's backlight
down and up again over a fifth of a second. The bench's stand-in brightnessctl
says what it was asked.
"""

import time

from bench.bench import SHELL
from bench.shell import Shell

PROBE = SHELL / "benchBrightnessProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_brightness_start.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "brightnessProbe"
        function ready(): bool {
            return Brightness.monitors.length > 0;
        }
        function level(): real {
            return Brightness.monitors[0]?.brightness ?? -1;
        }
    }
}
"""


def test_coming_up_reads_the_backlight_and_never_sets_it(bench):
    bench.shim_log.unlink(missing_ok=True)
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("brightnessProbe", "ready"))
    try:
        shell.start()
        time.sleep(2.0)
        assert shell.call("brightnessProbe", "level") == "0.5", "the backlight was not read"
        calls = bench.shim_log.read_text().splitlines() if bench.shim_log.exists() else []
        sets = [call for call in calls if call.startswith("brightnessctl") and " s " in f" {call} "]
        assert sets == [], f"the backlight was set as the shell came up: {sets[:5]} ({len(sets)} in all)"
    finally:
        shell.stop()
        shell.remove_probe()


def test_a_change_made_here_still_reaches_the_backlight(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("brightnessProbe", "ready"))
    try:
        shell.start()
        time.sleep(1.5)
        bench.shim_log.unlink(missing_ok=True)
        assert shell.call("brightness", "setLevel", "BENCH", "70") == "70"
        time.sleep(1.0)
        calls = bench.shim_log.read_text().splitlines() if bench.shim_log.exists() else []
        sets = [call for call in calls if " s " in f" {call} "]
        assert sets and sets[-1] == "brightnessctl --class backlight s 70% --quiet", sets
    finally:
        shell.stop()
        shell.remove_probe()
