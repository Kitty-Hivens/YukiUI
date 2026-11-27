"""A closed launcher leaves nothing on the screen to take the pointer.

Kept ready, which it is unless switched off, the launcher is built a moment
after the shell comes up and never taken down: closed, its window is parked, a
point that takes no pointer. Not kept, it shows its way out and then unloads,
its window taking the pointer only over the panel meanwhile. Its unloading
waits for the way out to reach its end, so a launcher closed in the moment it
opened, which never sets out at all, is checked as well as one closed after
showing.
"""

import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchLauncherProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry
import qs.blueberry.launcher

// Written by tests/blueberry/test_launcher_close.py for a test run, and removed after it.
ShellRoot {
    ExLauncher {}
    IpcHandler {
        target: "launcherProbe"
        function ready(): bool {
            return Config.ready;
        }
        function keepReady(on: bool): void {
            Config.options.blueberry.keepReady = on;
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
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        try:
            shell.call("launcherProbe", "keepReady", "true")
        except Exception:
            pass
        shell.stop()
        shell.remove_probe()


@pytest.fixture
def unkept(launcher):
    launcher.call("launcherProbe", "keepReady", "false")
    wait_until(lambda: len(launcher_layers(launcher.bench)) == 0, timeout=3, what="the parked launcher to go")
    return launcher


def launcher_layers(bench) -> list[dict]:
    found = []
    for monitor in bench.json("layers").values():
        for layer in monitor["levels"].values():
            found += [surface for surface in layer if surface["namespace"] == "quickshell:launcher"]
    return found


def parked(bench) -> bool:
    layers = launcher_layers(bench)
    return len(layers) == 1 and layers[0]["w"] <= 1 and layers[0]["h"] <= 1


def full_screen(bench) -> bool:
    layers = launcher_layers(bench)
    return len(layers) == 1 and layers[0]["w"] > 1000 and layers[0]["h"] > 600


def test_a_kept_launcher_is_built_ahead_and_parked(bench, launcher):
    # Never opened, it is there all the same, as a point.
    wait_until(lambda: parked(bench), timeout=8, what="the launcher to be built ahead and parked")


def test_a_kept_launcher_closes_back_to_its_park(bench, launcher):
    wait_until(lambda: parked(bench), timeout=8, what="the launcher to be parked")
    launcher.call("search", "open")
    wait_until(lambda: full_screen(bench), timeout=3, what="the launcher to take the screen")
    time.sleep(0.5)
    launcher.call("search", "close")
    wait_until(lambda: parked(bench), timeout=3, what="the launcher to go back to its park")
    # And comes out of it again.
    launcher.call("search", "open")
    wait_until(lambda: full_screen(bench), timeout=3, what="the launcher to take the screen again")
    launcher.call("search", "close")
    wait_until(lambda: parked(bench), timeout=3, what="the launcher to be parked again")


def test_a_kept_launcher_closed_as_it_opened_goes_back_to_its_park(bench, launcher):
    wait_until(lambda: parked(bench), timeout=8, what="the launcher to be parked")
    launcher.call("launcherProbe", "flick")
    time.sleep(0.3)
    wait_until(lambda: parked(bench), timeout=3, what="the launcher to stay parked")


def test_a_launcher_closed_after_showing_goes(bench, unkept):
    unkept.call("search", "open")
    wait_until(lambda: len(launcher_layers(bench)) == 1, what="the launcher to open")
    time.sleep(0.5)
    unkept.call("search", "close")
    wait_until(lambda: len(launcher_layers(bench)) == 0, timeout=3, what="the launcher's window to go")


def test_a_launcher_closed_as_it_opened_goes(bench, unkept):
    unkept.call("launcherProbe", "flick")
    time.sleep(0.3)
    wait_until(lambda: len(launcher_layers(bench)) == 0, timeout=3, what="the launcher's window to go")
