"""A closed launcher leaves nothing on the screen to take the pointer.

Closed, the launcher shows its way out and then unloads, its window taking the
pointer only over the panel meanwhile. Its unloading waits for the way out to
reach its end, so a launcher closed in the moment it opened, which never sets
out at all, is checked as well as one closed after showing.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchLauncherProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.experimental
import qs.experimental.launcher

// Written by tests/experimental/test_launcher_close.py for a test run, and removed after it.
ShellRoot {
    ExLauncher {}
    IpcHandler {
        target: "launcherProbe"
        function ready(): bool {
            return true;
        }
        // Opened and closed in one go, as a quick second press of Super does.
        function flick(): void {
            ExStates.launcherOpen = true;
            ExStates.launcherOpen = false;
        }
    }
}
"""


@pytest.fixture
def launcher(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("launcherProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def launcher_layers(bench) -> int:
    count = 0
    for monitor in bench.json("layers").values():
        for layer in monitor["levels"].values():
            count += sum(1 for surface in layer if surface["namespace"] == "quickshell:launcher")
    return count


def test_a_launcher_closed_after_showing_goes(bench, launcher):
    launcher.call("search", "open")
    wait_until(lambda: launcher_layers(bench) == 1, what="the launcher to open")
    time.sleep(0.5)
    launcher.call("search", "close")
    wait_until(lambda: launcher_layers(bench) == 0, timeout=3, what="the launcher's window to go")


def test_a_launcher_closed_as_it_opened_goes(bench, launcher):
    launcher.call("launcherProbe", "flick")
    time.sleep(0.3)
    wait_until(lambda: launcher_layers(bench) == 0, timeout=3, what="the launcher's window to go")
    assert not launcher.errors()
