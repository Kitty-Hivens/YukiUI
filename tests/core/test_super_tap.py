"""Super tapped alone toggles the menu of every environment, and Super used in a
combination does not.

The binds are read out of the session's own keybinds.lua, since which flags they
carry is the whole matter: with a plain bind Hyprland 0.57 delivers the release
whatever came while the key was held, and it reached the shell after every
combination.
"""

import re
import subprocess
import time

import pytest

from bench.bench import REPO, SHELL
from bench.shell import Shell

KEYBINDS = (REPO / "dots/.config/hypr/hyprland/keybinds.lua").read_text()
TAP_BINDS = re.findall(r'^hl\.bind\("SUPER \+ SUPER_[LR]", hl\.dsp\.global\("quickshell:searchToggleRelease"\).*$', KEYBINDS, re.M)

PROBE = SHELL / "benchSuperTapProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Written by tests/core/test_super_tap.py for a test run, and removed after it.
ShellRoot {
    id: probe
    property int released: 0
    GlobalShortcut {
        name: "searchToggleRelease"
        onReleased: probe.released++
    }
    IpcHandler {
        target: "tapProbe"
        function ready(): bool {
            return true;
        }
        function count(): string {
            return String(probe.released);
        }
    }
}
"""

HOLD = ("-P", "Super_L", "-M", "logo")
LET_GO = ("-m", "logo", "-p", "Super_L")


# After the desk, which reloads the config and with it every bind made here.
@pytest.fixture
def tap(bench, desk):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("tapProbe", "ready"))
    try:
        shell.start()
        assert len(TAP_BINDS) == 2
        for bind in TAP_BINDS:
            bench.eval(bind)
        bench.eval('hl.bind("SUPER + J", hl.dsp.exec_cmd("true"))')
        bench.eval('hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })')
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval('hl.unbind("SUPER + SUPER_L") hl.unbind("SUPER + SUPER_R") hl.unbind("SUPER + J") hl.unbind("SUPER + mouse:272")')


def released_after(shell, desk, *steps) -> int:
    before = int(shell.call("tapProbe", "count"))
    desk.keyboard.type(*HOLD, *steps, *LET_GO)
    time.sleep(0.35)
    return int(shell.call("tapProbe", "count")) - before


def test_a_tap_alone_toggles(tap, desk):
    assert released_after(tap, desk) == 1


def test_a_bound_combination_does_not(tap, desk):
    assert released_after(tap, desk, "-k", "j") == 0
    assert released_after(tap, desk) == 1, "the tap after a combination was lost"


def test_an_unbound_combination_does_not(tap, desk):
    assert released_after(tap, desk, "-k", "y") == 0
    assert released_after(tap, desk) == 1, "the tap after a combination was lost"


def test_a_click_while_held_does_not(bench, tap, desk):
    window = desk.wayland()
    x, y = window.client()["at"]
    pointer = desk.pointer()
    pointer.move(x + 60, y + 60)
    before = int(tap.call("tapProbe", "count"))
    held = subprocess.Popen(["wtype", *HOLD, "-s", "700", *LET_GO], env=bench.environment())
    time.sleep(0.25)
    pointer.press()
    time.sleep(0.05)
    pointer.release()
    held.wait()
    time.sleep(0.35)
    assert int(tap.call("tapProbe", "count")) == before
    assert released_after(tap, desk) == 1, "the tap after a click was lost"
