"""Touchpad gestures, as the settings have them.

A gesture once made cannot be taken back short of a reload, so the shell
writes the gestures down and the environment's compositor rules make them as
they load. The bench has no touchpad, so what is checked is what the rules
make of the file and what the shell writes into it.
"""

import json

import pytest

from bench.bench import RULES, SHELL, wait_until
from bench.shell import Shell


def gestures_made(bench) -> list[str]:
    """The gestures the rules make as they load, read by running them with hl.gesture written down."""
    lua = ('(function() local seen = {} local real = hl.gesture '
           'hl.gesture = function(g) seen[#seen + 1] = g.fingers .. " " .. g.direction .. " " '
           '.. (type(g.action) == "string" and g.action or type(g.action)) end '
           f'local ok, err = pcall(dofile, "{RULES}") hl.gesture = real '
           'if not ok then return "error " .. tostring(err) end return table.concat(seen, ",") end)()')
    try:
        return [entry for entry in bench.lua_value(lua).split(",") if entry]
    finally:
        # Run once more, the rules made their window rules and binds twice.
        bench.reload()


def gestures_file(bench):
    return bench.state_home / "yuki/gestures"


@pytest.fixture
def no_gestures_file(bench):
    gestures_file(bench).unlink(missing_ok=True)
    yield
    gestures_file(bench).unlink(missing_ok=True)


def test_without_a_file_the_gestures_are_as_before(bench, no_gestures_file):
    assert gestures_made(bench) == ["3 swipe move", "3 pinch fullscreen", "4 horizontal workspace"]


def test_the_file_is_read_and_only_known_actions_are_made(bench, no_gestures_file):
    path = gestures_file(bench)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("4\thorizontal\tworkspace\n3\tup\tsearch\n3\tdown\tshowDesktop\n"
                    "3\tleft\tsearch\n9\tup\tsearch\n3\tdown\tos.execute\n4\tup\tnotifications\n")
    made = gestures_made(bench)
    assert made == ["4 horizontal workspace", "3 up function", "3 down function", "4 up function"]


PROBE = SHELL / "benchGesturesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.experimental.input

// Written by tests/experimental/test_gestures.py for a test run, and removed after it.
ShellRoot {
    ExGestures {}
    IpcHandler {
        target: "gesturesProbe"
        function ready(): bool {
            return Config.ready;
        }
        function set(fingers: string, json: string): void {
            const wanted = JSON.parse(json);
            for (const key of Object.keys(wanted))
                Config.options.experimental.gestures[fingers][key] = wanted[key];
        }
    }
}
"""


@pytest.fixture
def writer(bench, no_gestures_file):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("gesturesProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def written(bench, lines: list[str]):
    expected = "".join(f"{line}\n" for line in lines)
    wait_until(lambda: gestures_file(bench).exists() and gestures_file(bench).read_text() == expected,
               what=f"the gestures file to read {lines}")


def test_the_shell_writes_the_gestures_down(bench, writer):
    written(bench, ["3\tswipe\tmove", "3\tpinch\tfullscreen", "4\thorizontal\tworkspace", "4\tup\tsearch", "4\tdown\tshowDesktop"])
    mark = bench.events.mark()
    writer.call("gesturesProbe", "set", "three", json.dumps({"mode": "custom", "sideways": "none", "up": "notifications", "down": "maximize"}))
    writer.call("gesturesProbe", "set", "four", json.dumps({"mode": "none"}))
    written(bench, ["3\tup\tnotifications", "3\tdown\tmaximize"])
    # And the compositor read them again.
    bench.events.wait("configreloaded", since=mark)
