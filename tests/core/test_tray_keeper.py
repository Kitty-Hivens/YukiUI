"""The tray's icons outlive a restart of the shell.

Many programs register their tray icon once, with whoever answers as the
StatusNotifierWatcher, and never again, and the shell's tray answered as that
watcher itself, so a restart of the shell lost those icons. yuki-tray, which
the shell starts and which outlives it, copies what is registered while the
shell holds the watcher's name and takes it over when the shell lets go.

The test's own session bus stands in for the person's, which outlives the
shell the same way: a shell with a bus of its own takes the bus down with it.
"""

import json
import os
import subprocess
import sys

import pytest

from bench.bench import REPO, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchTrayKeeperProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.core.services

// Written by tests/core/test_tray_keeper.py for a test run, and removed after it.
ShellRoot {
    // The tray is read from the start, as a desktop's bar reads it.
    readonly property var icons: SystemTray.items.values
    Component.onCompleted: TrayKeeper.load()

    IpcHandler {
        target: "trayProbe"
        function ids(): string {
            return JSON.stringify(SystemTray.items.values.map(item => item.id));
        }
    }
}
"""

CLIENT = REPO / "tests/bench/clients/tray_item.py"


@pytest.fixture
def session_bus(monkeypatch):
    """A session bus of the test's own, outliving the shells started on it."""
    daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                              stdout=subprocess.PIPE, text=True)
    address = daemon.stdout.readline().strip()
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", address)
    try:
        yield address
    finally:
        daemon.terminate()
        daemon.wait(5)


@pytest.fixture
def tray(bench, session_bus):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("trayProbe", "ids"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "the tray reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def ids(shell) -> list[str]:
    return json.loads(shell.call("trayProbe", "ids"))


def test_an_icon_registered_once_is_back_after_the_shell_restarts(bench, tray):
    # Registered once and never again, as Easy Effects does.
    program = subprocess.Popen([sys.executable, str(CLIENT)], env=dict(os.environ),
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert json.loads(program.stdout.readline())["ready"]
        wait_until(lambda: "bench-tray" in ids(tray), what="the icon in the tray")

        tray.restart()
        wait_until(lambda: "bench-tray" in ids(tray), timeout=8, what="the icon back after the restart")

        # And the icon goes with its program.
        program.stdin.close()
        program.wait(5)
        wait_until(lambda: "bench-tray" not in ids(tray), what="the icon to go with its program")
    finally:
        if program.poll() is None:
            program.kill()
