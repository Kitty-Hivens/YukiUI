"""Notification cards, with a notification server on a bus of the probe's own.

A card keeps what its notification said, to show while it leaves. The
shell's wrapper of a notification outlives what the server held by a moment,
with every field empty by then, and a card that went on following it left
blank: on a click, on Clear all, and when the sender closed it.
"""

import subprocess
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

from .test_markup import listener  # noqa: F401

PROBE = SHELL / "benchNotificationProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.experimental.notifications

// Written by tests/experimental/test_notifications.py for a test run, and removed after it.
ShellRoot {
    id: probe

    // The first notification to arrive, and a card for it made once and kept.
    property var held: null
    property bool started: false
    Connections {
        target: Notifications
        function onNotify(notif) {
            if (probe.started)
                return;
            probe.held = notif;
            probe.started = true;
        }
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 200
        Loader {
            id: slot
            active: probe.started
            sourceComponent: NotificationCard {
                notif: probe.held
            }
        }
    }

    IpcHandler {
        target: "notificationProbe"
        function ready(): string {
            return "yes";
        }
        function count(): int {
            return Notifications.list.length;
        }
        function shown(): string {
            return slot.item ? JSON.stringify({ summary: slot.item.shown.summary, body: slot.item.shown.body }) : "";
        }
    }
}
"""


@pytest.fixture
def notifications(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("notificationProbe", "ready"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def notify(shell, summary, body) -> int:
    result = subprocess.run(["notify-send", "-p", "-t", "600000", summary, body], env=shell.environment(),
                            capture_output=True, text=True, check=True)
    return int(result.stdout.strip())


def test_card_keeps_its_words_when_the_sender_closes_it(notifications):
    shell = notifications
    sent = notify(shell, "Hello", "From the test")
    wait_until(lambda: shell.call("notificationProbe", "shown") == '{"summary":"Hello","body":"From the test"}',
               what="the card to show the notification")
    subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                    "--object-path", "/org/freedesktop/Notifications",
                    "--method", "org.freedesktop.Notifications.CloseNotification", str(sent)],
                   env=shell.environment(), capture_output=True, check=True)
    wait_until(lambda: shell.call("notificationProbe", "count") == "0", what="the notification to go")
    assert shell.call("notificationProbe", "shown") == '{"summary":"Hello","body":"From the test"}'
    assert not shell.errors()


def test_card_follows_a_notification_replaced_in_place(notifications):
    shell = notifications
    sent = notify(shell, "Downloading", "10%")
    wait_until(lambda: shell.call("notificationProbe", "shown") == '{"summary":"Downloading","body":"10%"}',
               what="the card to show the notification")
    subprocess.run(["notify-send", "-r", str(sent), "-t", "600000", "Downloading", "80%"], env=shell.environment(), check=True)
    wait_until(lambda: shell.call("notificationProbe", "shown") == '{"summary":"Downloading","body":"80%"}',
               what="the card to follow the replacement")


def test_pictures_from_elsewhere_are_not_fetched(notifications, listener):
    # The body is often someone else's words, a chat message passed on as it
    # came, and a picture in it pointing at a server would tell that server
    # the message was shown.
    shell = notifications
    body = f'Hi <img src="{listener.url("body.png")}"> there'
    subprocess.run(["notify-send", "-t", "600000", "-i", listener.url("icon.png"),
                    f"--hint=string:image-path:{listener.url('image.png')}", "Message", body],
                   env=shell.environment(), check=True)
    wait_until(lambda: '"summary":"Message"' in shell.call("notificationProbe", "shown"),
               what="the card to show the notification")
    time.sleep(1.5)
    assert listener.requests == []
    assert shell.call("notificationProbe", "shown") == '{"summary":"Message","body":"Hi  there"}'
