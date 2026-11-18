"""The pen and tablet page of the settings, against a fake tablet driver.

The driver's daemon is stood up by the test on a socket of its own, the way
tests/core/test_otd_helper.py does it, so the person's tablet is never asked or
changed. The bench's one screen is 1920x1080, and the fake tablet 160x100 mm.
"""

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

from core.test_otd_helper import FakeDaemon

PROBE = SHELL / "benchTabletPageProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.blueberry.settings

// Written by tests/blueberry/test_tablet_page.py for a test run, and removed after it.
ShellRoot {
    id: probe

    FloatingWindow {
        title: "benchSettings"
        implicitWidth: 1200
        implicitHeight: 900
        ExSettings {
            id: settings
            anchors.fill: parent
        }
    }

    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }

    IpcHandler {
        target: "tabletPageProbe"
        function open(): void {
            settings.open("pen");
        }
        function here(): string {
            return settings.shownPage;
        }
        function tablet(): string {
            return PenTablet.tablet?.name ?? "";
        }
        function warned(): bool {
            return probe.find(settings, item => item.text === "The pen reaches only part of the screen")?.visible ?? false;
        }
        function press(text: string): bool {
            const button = probe.find(settings, item => item.text === text && item.clicked !== undefined && item.kind !== undefined);
            if (!button)
                return false;
            button.clicked();
            return true;
        }
        function pickArea(index: int): bool {
            const row = probe.find(settings, item => item.text === "The pen reads on" && item.expanded !== undefined);
            const dropdown = row ? probe.find(row, item => item.activated !== undefined && item.currentIndex !== undefined) : null;
            if (!dropdown)
                return false;
            dropdown.activated(index);
            return true;
        }
    }
}
"""


@pytest.fixture
def daemon(tmp_path):
    fake = FakeDaemon(tmp_path / "otd.sock")
    # Left from a smaller screen, as a laptop's would be.
    fake.settings["Profiles"][0]["AbsoluteModeSettings"]["Display"] = {"Width": 1280.0, "Height": 720.0, "X": 640.0, "Y": 360.0, "Rotation": 0.0}
    yield fake
    fake.close()


@pytest.fixture
def page(bench, daemon, tmp_path):
    env = {"YUKI_OTD_SOCKET": str(tmp_path / "otd.sock"), "YUKI_OTD_SETTINGS": str(tmp_path / "otd/settings.json")}
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("tabletPageProbe", "here"), env=env)
    try:
        shell.start()
        wait_until(lambda: any(c["title"] == "benchSettings" for c in bench.clients()), what="the settings window")
        shell.call("tabletPageProbe", "open")
        wait_until(lambda: shell.call("tabletPageProbe", "here") == "pen", timeout=10, what="the pen page")
        wait_until(lambda: shell.call("tabletPageProbe", "tablet") == "Bench Tablet", what="the tablet read from the driver")
        yield shell
        assert not shell.errors(), "the page reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def absolute(daemon):
    return daemon.settings["Profiles"][0]["AbsoluteModeSettings"]


def test_a_screen_area_left_from_another_screen_is_said_and_set_right(daemon, page, tmp_path):
    wait_until(lambda: page.call("tabletPageProbe", "warned") == "true", what="the warning about part of the screen")
    assert page.call("tabletPageProbe", "press", "Use the whole screen") == "true"
    wait_until(lambda: absolute(daemon)["Display"]["Width"] == 1920.0, what=f"the whole screen handed over, last {absolute(daemon)['Display']}")
    assert absolute(daemon)["Display"] == {"Width": 1920.0, "Height": 1080.0, "X": 960.0, "Y": 540.0, "Rotation": 0.0}
    # Kept where the driver reads it at start.
    written = json.loads((tmp_path / "otd/settings.json").read_text())
    assert written["Profiles"][0]["AbsoluteModeSettings"]["Display"]["Width"] == 1920.0
    wait_until(lambda: page.call("tabletPageProbe", "warned") == "false", what="the warning gone")


def test_the_screens_shape_is_the_widest_such_area_in_the_middle(daemon, page):
    assert page.call("tabletPageProbe", "pickArea", "1") == "true"
    wait_until(lambda: absolute(daemon)["Tablet"]["Width"] == 160.0, what=f"the fitted area handed over, last {absolute(daemon)['Tablet']}")
    # 16:9 on a 160 x 100 tablet: all of its width, 90 of its height.
    assert absolute(daemon)["Tablet"] == {"Width": 160.0, "Height": 90.0, "X": 80.0, "Y": 50.0, "Rotation": 0.0}
    # And the screen area with it, so the two agree.
    assert absolute(daemon)["Display"]["Width"] == 1920.0
    time.sleep(0.3)
