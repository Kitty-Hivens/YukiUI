"""An application's page in the settings.

Opened as the launcher's menu opens it, by "app:" and the entry's id. Whether
the application starts with the session is written as the desktop keeps it, in
the autostart folder of the bench's own configuration, and its notifications
are turned away by its id in the shell's configuration. The application is a
desktop entry of the test's own, in a data folder of its own.
"""

import json
import os
import subprocess

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchAppPageProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.blueberry.settings

// Written by tests/blueberry/test_app_page.py for a test run, and removed after it.
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
        target: "appPageProbe"
        function ready(): bool {
            return Config.ready && DesktopEntries.byId("bench-app") !== null;
        }
        function open(key: string): void {
            settings.open(key);
        }
        function here(): string {
            return settings.shownPage;
        }
        function shows(text: string): bool {
            return probe.find(settings, item => item.text === text && item.visible) !== null;
        }
        // The switch in the row of that name.
        function toggle(row: string): bool {
            const card = probe.find(settings, item => item.text === row && item.leads !== undefined);
            const toggle = card ? probe.find(card.contentItem, item => item.toggled !== undefined && item.checked !== undefined) : null;
            if (!toggle)
                return false;
            toggle.checked = !toggle.checked;
            toggle.toggled();
            return true;
        }
        function checked(row: string): bool {
            const card = probe.find(settings, item => item.text === row && item.leads !== undefined);
            return probe.find(card?.contentItem ?? null, item => item.toggled !== undefined && item.checked !== undefined)?.checked ?? false;
        }
        function blocked(): string {
            return JSON.stringify([...Config.options.notifications.blockedApps]);
        }
        function unblock(): void {
            Config.options.notifications.blockedApps = [];
        }
    }
}
"""


@pytest.fixture
def page(bench, tmp_path):
    apps = tmp_path / "share/applications"
    apps.mkdir(parents=True)
    (apps / "bench-app.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Bench app\nComment=Stands in for an application\nExec=sleep 1\n")
    dirs = f"{tmp_path / 'share'}:{os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')}"
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("appPageProbe", "ready"), env={"XDG_DATA_DIRS": dirs})
    try:
        shell.start()
        wait_until(lambda: shell.call("appPageProbe", "ready") == "true", timeout=10, what="the entry to be read")
        yield shell
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        try:
            shell.call("appPageProbe", "unblock")
        except Exception:
            pass
        (bench.config_home / "autostart/bench-app.desktop").unlink(missing_ok=True)
        shell.stop()
        shell.remove_probe()


def test_the_page_opens_on_the_application(page):
    page.call("appPageProbe", "open", "app:bench-app")
    wait_until(lambda: page.call("appPageProbe", "here") == "app:bench-app", timeout=5, what="the page to open")
    assert page.call("appPageProbe", "shows", "Bench app") == "true"
    assert page.call("appPageProbe", "shows", "Start with the session") == "true"


def test_starting_with_the_session_is_written_and_taken_back(bench, page):
    page.call("appPageProbe", "open", "app:bench-app")
    wait_until(lambda: page.call("appPageProbe", "here") == "app:bench-app", timeout=5, what="the page to open")
    autostart = bench.config_home / "autostart/bench-app.desktop"
    assert page.call("appPageProbe", "toggle", "Start with the session") == "true"
    wait_until(lambda: autostart.exists(), timeout=5, what="the autostart entry to be written")
    assert "Exec=sleep 1" in autostart.read_text()
    wait_until(lambda: page.call("appPageProbe", "checked", "Start with the session") == "true", timeout=5, what="the switch to read on")
    assert page.call("appPageProbe", "toggle", "Start with the session") == "true"
    wait_until(lambda: not autostart.exists(), timeout=5, what="the autostart entry to go")


def test_notifications_are_turned_away_by_id(page):
    page.call("appPageProbe", "open", "app:bench-app")
    wait_until(lambda: page.call("appPageProbe", "here") == "app:bench-app", timeout=5, what="the page to open")
    assert page.call("appPageProbe", "toggle", "Allow notifications") == "true"
    wait_until(lambda: json.loads(page.call("appPageProbe", "blocked")) == ["bench-app"], timeout=3, what="the application to be turned away")
    assert page.call("appPageProbe", "toggle", "Allow notifications") == "true"
    wait_until(lambda: json.loads(page.call("appPageProbe", "blocked")) == [], timeout=3, what="the application to be let through again")
