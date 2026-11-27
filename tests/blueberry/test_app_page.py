"""An application's page in the settings.

Opened as the launcher's menu opens it, by "app:" and the entry's id. Whether
the application starts with the session is written as the desktop keeps it, in
the autostart folder of the bench's own configuration, and its notifications
are turned away by its id in the shell's configuration. The applications are
desktop entries of the test's own, in a data folder of its own that stands for
the user's, so they count as added by hand.
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
        function press(text: string): bool {
            const button = probe.find(settings, item => item.text === text && item.kind !== undefined && item.clicked !== undefined && item.visible);
            if (!button)
                return false;
            button.clicked();
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
    # An id of its own that ends in .desktop, as Telegram's does.
    (apps / "bench.app.desktop.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Bench dotted\nExec=sleep 1\n")
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("appPageProbe", "ready"), env={"XDG_DATA_HOME": str(tmp_path / "share")})
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
        for name in ("bench-app.desktop", "bench.app.desktop.desktop"):
            (bench.config_home / "autostart" / name).unlink(missing_ok=True)
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


def test_an_id_ending_in_desktop_is_found(page):
    page.call("appPageProbe", "open", "app:bench.app.desktop")
    wait_until(lambda: page.call("appPageProbe", "here") == "app:bench.app.desktop", timeout=5, what="the page to open")
    wait_until(lambda: page.call("appPageProbe", "shows", "Added to the list by hand or by another program") == "true",
               timeout=5, what="the entry to be found and told apart")


def test_the_question_of_taking_it_off_comes_back_after_cancel(page):
    question = "Move its entry to the trash?"
    page.call("appPageProbe", "open", "app:bench-app|uninstall")
    wait_until(lambda: page.call("appPageProbe", "shows", question) == "true", timeout=5, what="the question")
    assert page.call("appPageProbe", "here") == "app:bench-app", "the question is not part of the page's place"
    assert page.call("appPageProbe", "press", "Cancel") == "true"
    wait_until(lambda: page.call("appPageProbe", "shows", question) == "false", timeout=3, what="the question to go")
    page.call("appPageProbe", "open", "app:bench-app|uninstall")
    wait_until(lambda: page.call("appPageProbe", "shows", question) == "true", timeout=5, what="the question asked again")


def test_switching_off_an_applications_own_autostart_keeps_its_flags(bench, page):
    # Written by the application itself, starting it minimised. Switched off
    # and on again, it starts as it set itself to.
    autostart = bench.config_home / "autostart/bench-app.desktop"
    autostart.parent.mkdir(parents=True, exist_ok=True)
    autostart.write_text("[Desktop Entry]\nType=Application\nName=Bench app\nExec=sleep 1 --minimized\n")
    page.call("appPageProbe", "open", "app:bench-app")
    wait_until(lambda: page.call("appPageProbe", "checked", "Start with the session") == "true", timeout=5, what="the switch to read on")
    assert page.call("appPageProbe", "toggle", "Start with the session") == "true"
    wait_until(lambda: "Hidden=true" in autostart.read_text(), timeout=5, what="the autostart entry to be hidden")
    assert "--minimized" in autostart.read_text()
    wait_until(lambda: page.call("appPageProbe", "checked", "Start with the session") == "false", timeout=5, what="the switch to read off")
    assert page.call("appPageProbe", "toggle", "Start with the session") == "true"
    wait_until(lambda: "Hidden" not in autostart.read_text(), timeout=5, what="the autostart entry to be shown again")
    assert "Exec=sleep 1 --minimized" in autostart.read_text()
