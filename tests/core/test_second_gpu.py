"""Applications that ask for the second graphics card are started on it.

A desktop entry asks with PrefersNonDefaultGPU, Steam's does, and GNOME and KDE
start such an entry on the discrete card. The shell started every entry on the
card that drives the screen. The script that works out which entries ask and
how the second card is reached is tested here on folders and answers made for
the test; the last test starts two entries made for it through the shell on
the bench, with switcheroo-control stood in for by a busctl that answers as it
would, and reads back what each was started with.
"""

import importlib.util
import json
import os
from pathlib import Path

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

SCRIPT = SHELL / "scripts/apps/second-gpu.py"
spec = importlib.util.spec_from_file_location("second_gpu", SCRIPT)
second_gpu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(second_gpu)


def entry(folder: Path, name: str, extra: str = ""):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_text(f"[Desktop Entry]\nType=Application\nName={name}\nExec=true\n{extra}")


def test_entries_that_ask_are_found(tmp_path):
    apps = tmp_path / "share/applications"
    entry(apps, "steam.desktop", "PrefersNonDefaultGPU=true\n")
    entry(apps, "old-kde.desktop", "X-KDE-RunOnDiscreteGpu=true\n")
    entry(apps, "plain.desktop")
    entry(apps, "says-no.desktop", "PrefersNonDefaultGPU=false\n")
    entry(apps / "games", "nested.desktop", "PrefersNonDefaultGPU=true\n")
    assert second_gpu.preferring_entries([str(apps)]) == ["games-nested", "old-kde", "steam"]


def test_a_key_in_an_action_does_not_count(tmp_path):
    apps = tmp_path / "share/applications"
    entry(apps, "action.desktop", "Actions=Big;\n\n[Desktop Action Big]\nName=Big\nExec=true\nPrefersNonDefaultGPU=true\n")
    assert second_gpu.preferring_entries([str(apps)]) == []


def test_the_persons_own_entry_wins(tmp_path):
    own = tmp_path / "home/applications"
    system = tmp_path / "usr/applications"
    entry(system, "steam.desktop", "PrefersNonDefaultGPU=true\n")
    entry(own, "steam.desktop")
    entry(system, "other.desktop", "PrefersNonDefaultGPU=true\n")
    assert second_gpu.preferring_entries([str(own), str(system)]) == ["other"]


SWITCHEROO = {"type": "aa{sv}", "data": [
    {"Name": {"type": "s", "data": "AMD Renoir"}, "Environment": {"type": "as", "data": ["DRI_PRIME", "pci-0000_05_00_0"]},
     "Default": {"type": "b", "data": True}},
    {"Name": {"type": "s", "data": "NVIDIA GeForce GTX 1650 Ti Mobile"},
     "Environment": {"type": "as", "data": ["__GLX_VENDOR_LIBRARY_NAME", "nvidia", "__NV_PRIME_RENDER_OFFLOAD", "1",
                                             "__VK_LAYER_NV_optimus", "NVIDIA_only"]},
     "Default": {"type": "b", "data": False}},
]}


def test_switcheroo_names_the_card_that_is_not_the_default():
    assert second_gpu.switcheroo_environment(json.dumps(SWITCHEROO)) == {
        "__GLX_VENDOR_LIBRARY_NAME": "nvidia", "__NV_PRIME_RENDER_OFFLOAD": "1", "__VK_LAYER_NV_optimus": "NVIDIA_only"}


def test_switcheroo_with_one_card_names_nothing():
    one = {"type": "aa{sv}", "data": [SWITCHEROO["data"][0]]}
    assert second_gpu.switcheroo_environment(json.dumps(one)) == {}
    assert second_gpu.switcheroo_environment("not json") == {}


def card(drm: Path, name: str, vendor: str):
    (drm / name / "device").mkdir(parents=True)
    (drm / name / "device/vendor").write_text(vendor + "\n")


@pytest.mark.parametrize("cards, driver, expected", [
    ({"card0": "0x1002", "card1": "0x10de"}, True, True),
    ({"card0": "0x10de"}, True, False),
    ({"card0": "0x1002", "card1": "0x10de"}, False, False),
    ({"card0": "0x8086"}, False, False),
])
def test_an_nvidia_card_beside_another(tmp_path, cards, driver, expected):
    drm = tmp_path / "drm"
    for name, vendor in cards.items():
        card(drm, name, vendor)
    (drm / "card0-eDP-1").mkdir(parents=True)
    version = tmp_path / "version"
    if driver:
        version.write_text("NVRM version: 620.73.04\n")
    assert second_gpu.nvidia_beside_another(str(drm), str(version)) is expected


PROBE = SHELL / "benchAppLaunchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_second_gpu.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "launchProbe"
        function ready(): string {
            return AppLaunch.hasSecondGpu && DesktopEntries.byId("yuki-gpu-wants") ? "yes" : "";
        }
        function run(id: string): void {
            AppLaunch.run(DesktopEntries.byId(id));
        }
    }
}
"""


@pytest.fixture
def launcher(bench, tmp_path):
    data = tmp_path / "data"
    apps = data / "applications"
    apps.mkdir(parents=True)
    record = tmp_path / "record.sh"
    record.write_text('#!/bin/sh\nenv > "$(dirname "$0")/$1.env"\n')
    record.chmod(0o755)
    (apps / "yuki-gpu-wants.desktop").write_text(
        f"[Desktop Entry]\nType=Application\nName=Wants\nExec={record} wants\nPrefersNonDefaultGPU=true\n")
    (apps / "yuki-gpu-plain.desktop").write_text(
        f"[Desktop Entry]\nType=Application\nName=Plain\nExec={record} plain\n")
    fakebin = tmp_path / "bin"
    fakebin.mkdir()
    busctl = fakebin / "busctl"
    busctl.write_text("#!/bin/sh\ncat <<'EOF'\n" + json.dumps(SWITCHEROO) + "\nEOF\n")
    busctl.chmod(0o755)

    env = {"XDG_DATA_HOME": str(data), "PATH": f"{fakebin}:{bench.environment()['PATH']}"}
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("launchProbe", "ready"), env=env)
    shell.start()
    wait_until(lambda: shell.call("launchProbe", "ready") == "yes", timeout=15, what="the second card to be known")
    yield shell, tmp_path
    shell.stop()
    shell.remove_probe()


def environment_of(path: Path) -> dict:
    text = wait_until(lambda: path.exists() and path.read_text(), timeout=10, what=f"{path.name} to be written")
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def test_an_entry_that_asks_starts_on_the_second_card_and_one_that_does_not_does_not(launcher):
    shell, folder = launcher
    shell.call("launchProbe", "run", "yuki-gpu-wants")
    shell.call("launchProbe", "run", "yuki-gpu-plain")
    wants = environment_of(folder / "wants.env")
    plain = environment_of(folder / "plain.env")
    assert wants.get("__NV_PRIME_RENDER_OFFLOAD") == "1"
    assert wants.get("__GLX_VENDOR_LIBRARY_NAME") == "nvidia"
    assert "__NV_PRIME_RENDER_OFFLOAD" not in plain
