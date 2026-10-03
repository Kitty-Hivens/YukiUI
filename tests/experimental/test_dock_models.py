"""Lists in the dock that are rebuilt from fresh objects on every pass.

Quickshell's ScriptModel, given objects, compares the first rows by key, and
from the first row whose key matches but whose object does not it rewrites
the rows by place without looking at keys again. A list made anew each time
therefore never moved or removed a row: the delegate that had been one entry
was handed the next one's data. The dock gives its models the keys alone.

Run on the real tray component, its entries made anew on every change, as the
dock makes them.
"""

import pytest

from bench.bench import SHELL
from bench.shell import Shell

PROBE = SHELL / "benchDockModelProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.experimental.dock

// Written by tests/experimental/test_dock_models.py for a test run, and removed after it.
ShellRoot {
    id: probe

    property var entries: []
    // Every delegate seen so far, so the same one is known again.
    property var seen: []

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 60
        DockTray {
            id: tray
            entries: probe.entries
        }
    }

    IpcHandler {
        target: "dockModel"

        // Fresh objects every time, as the dock builds its entries.
        function set(keys: string): void {
            probe.entries = keys.length === 0 ? [] : keys.split(",").map(key => ({ key: key, item: null, state: "" }));
        }
        // Each icon in order as key#delegate, the number naming the delegate.
        function list(): string {
            const out = [];
            for (let place = 1; ; place++) {
                const icon = tray.iconAt(place);
                if (!icon)
                    break;
                let number = probe.seen.indexOf(icon);
                if (number < 0) {
                    probe.seen.push(icon);
                    number = probe.seen.length - 1;
                }
                const key = typeof icon.modelData === "string" ? icon.modelData : icon.modelData.key;
                out.push(`${key}#${number}`);
            }
            return out.join(",");
        }
    }
}
"""


@pytest.fixture(scope="module")
def tray(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dockModel", "list"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def test_an_entry_gone_takes_its_own_icon_with_it(tray):
    tray.call("dockModel", "set", "a,b,c")
    assert tray.call("dockModel", "list") == "a#0,b#1,c#2"
    tray.call("dockModel", "set", "a,c")
    # The icon that was c is still c. Rewritten by place, b's icon became c.
    assert tray.call("dockModel", "list") == "a#0,c#2"
    assert not tray.errors()


def test_an_entry_moved_keeps_its_icon(tray):
    tray.call("dockModel", "set", "x,y,z")
    before = dict(item.split("#") for item in tray.call("dockModel", "list").split(","))
    tray.call("dockModel", "set", "z,x,y")
    after = tray.call("dockModel", "list")
    assert after == f"z#{before['z']},x#{before['x']},y#{before['y']}"
