"""A tray menu's checkable entries stay checkable once one of them is picked.

Easy Effects announces a picked preset by the toggle state alone, as the
DBusMenu protocol has it: an update carries only what changed. Quickshell read
such an update as the whole set of properties and reset what it left out, so
the entries lost their checkmarks and were drawn as plain ones. Fixed in the
shell's Quickshell fork.
"""

import json
import subprocess
import sys

import pytest

from bench.bench import REPO, SHELL, BenchError, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchTrayMenuProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// Written by tests/blueberry/test_tray_menu_toggles.py for a test run, and removed after it.
ShellRoot {
    QsMenuOpener {
        id: opener
        menu: SystemTray.items.values[0]?.menu ?? null
    }
    IpcHandler {
        target: "trayMenu"
        function ready(): bool {
            return true;
        }
        // Each entry as text, its button type and its check state.
        function entries(): string {
            return JSON.stringify((opener.children?.values ?? []).map(entry => [entry.text, entry.buttonType, entry.checkState]));
        }
    }
}
"""

CHECKBOX = 1
CHECKED = 2


@pytest.fixture
def tray(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("trayMenu", "ready"), own_bus=True)
    client = None
    try:
        shell.start()
        client = subprocess.Popen([sys.executable, str(REPO / "tests/bench/clients/tray_item.py")], env=shell.environment(),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        assert json.loads(client.stdout.readline()) == {"ready": True}
        yield shell, client
    finally:
        if client:
            client.kill()
            client.wait()
        shell.stop()
        shell.remove_probe()


def settle(shell, expected: list, what: str):
    """Waits for the menu to read as expected, and says what it read last when it does not."""
    seen = []
    try:
        wait_until(lambda: seen.append(json.loads(shell.call("trayMenu", "entries"))) or seen[-1] == expected, what=what)
    except BenchError:
        raise AssertionError(f"{what}: last read {seen[-1] if seen else None}") from None


def test_picking_an_entry_keeps_both_checkable(tray):
    shell, client = tray
    settle(shell, [["First", CHECKBOX, CHECKED], ["Second", CHECKBOX, 0]], "the menu as the program lists it")
    client.stdin.write("pick Second\n")
    client.stdin.flush()
    assert json.loads(client.stdout.readline()) == {"ok": "Second"}
    settle(shell, [["First", CHECKBOX, 0], ["Second", CHECKBOX, CHECKED]], "Second checked and both still checkmarks")
    assert not shell.errors()
