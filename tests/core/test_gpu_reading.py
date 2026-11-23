"""The card that drives the screen is read all the time, as the processor is.

It used to be read only while the game bar's performance widget was open, a
second at a time, so the widget opened on a dash and an empty graph, and its
graph jumped about beside the processor's and memory's, read every few
seconds. Any other card is still read only while someone looks, since asking
wakes a card that has gone to sleep.

Reads the machine's real card: the bench runs on it.
"""

import importlib.util
import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchGpuReadingProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services

// Written by tests/core/test_gpu_reading.py for a test run, and removed after it.
ShellRoot {
    Component.onCompleted: {
        Config.ready;
        ResourceUsage.cpuUsage;
    }
    IpcHandler {
        target: "gpuProbe"
        function ready(): string {
            return ResourceUsage.gpuSearched ? "yes" : "";
        }
        function state(): string {
            return JSON.stringify({
                kind: ResourceUsage.gpuKind,
                drivesScreen: ResourceUsage.gpuDrivesScreen,
                reading: ResourceUsage.gpuReading,
                watchers: ResourceUsage.gpuWatchers,
                history: ResourceUsage.gpuUsageHistory.length,
                interval: ResourceUsage.updateInterval
            });
        }
        function setInterval(ms: int): void {
            Config.options.resources.updateInterval = ms;
        }
    }
}
"""


@pytest.fixture
def probe(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("gpuProbe", "ready"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def state(probe) -> dict:
    return json.loads(probe.call("gpuProbe", "state"))


def test_the_card_driving_the_screen_is_read_with_nobody_looking(probe):
    first = state(probe)
    if not first["kind"]:
        pytest.skip("this machine's card says neither how busy it is nor its clock")
    if not first["drivesScreen"]:
        pytest.skip("the card found does not drive the screen")
    assert first["watchers"] == 0
    assert first["reading"]
    # Quicker than the default, for the test not to wait half a minute.
    probe.call("gpuProbe", "setInterval", "1000")
    wait_until(lambda: state(probe)["history"] >= 3, timeout=30, what=f"readings to pile up, last {state(probe)}")


def shares(busy_before, busy_after, passed=19_200_000):
    """The share gpu_busy.py gives a program whose xe cycles went from one to the other in a second."""
    spec = importlib.util.spec_from_file_location("gpu_busy", SHELL / "scripts/system/gpu_busy.py")
    gpu_busy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gpu_busy)
    before = {"1": {"rcs": (busy_before, 1000, 1, "cycles")}}
    after = {"1": {"rcs": (busy_after, 1000 + passed, 1, "cycles")}}
    return gpu_busy.shares(before, after, 1.0)


def test_a_count_that_starts_over_is_still_a_load():
    # The cycles xe keeps for a program fall by 2^32 as they pass it. Left
    # out of the sum, the one program drawing made the card look idle.
    before = 5_000_000_000
    after = before + 13_000_000 - (1 << 32)
    assert shares(before, after) == pytest.approx({"rcs": 13_000_000 / 19_200_000})


def test_a_count_that_falls_for_another_reason_is_not_a_load():
    assert shares(5_000_000_000, 4_000_000_000) == {}
