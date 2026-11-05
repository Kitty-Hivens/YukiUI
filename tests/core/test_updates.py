"""The updates service says what the checker said, including that it could not.

Counted through a pipe, a check that failed read as nothing to update, so with the
network down the settings said the system was up to date.
"""

import json
import os
from pathlib import Path

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

FAKES = Path(__file__).resolve().parent.parent / "blueberry/fakes/updates"
PROBE = SHELL / "benchUpdatesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_updates.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "updatesProbe"
        function ready(): bool {
            return Updates.available;
        }
        function check(): void {
            Updates.refresh();
        }
        function state(): string {
            return JSON.stringify({ checking: Updates.checking, count: Updates.count, failed: Updates.failed, packages: Updates.packages, checked: Updates.lastChecked !== null });
        }
    }
}
"""


@pytest.fixture
def updates(bench, tmp_path, monkeypatch):
    answer = tmp_path / "updates"
    monkeypatch.setenv("PATH", f"{FAKES}:{os.environ['PATH']}")
    monkeypatch.setenv("FAKE_UPDATES", str(answer))
    answer.write_text("linux 7.2.14-1 -> 7.2.15-1\nkitty 0.40-1 -> 0.41-1\n")
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("updatesProbe", "ready"))
    try:
        shell.start()
        yield shell, answer
    finally:
        shell.stop()
        shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("updatesProbe", "state"))


def check(shell) -> dict:
    shell.call("updatesProbe", "check")
    wait_until(lambda: not state(shell)["checking"], what="the check to end")
    return state(shell)


def test_the_checker_is_taken_at_its_word(updates):
    shell, answer = updates
    wait_until(lambda: state(shell)["checked"], what="the first check")
    seen = state(shell)
    assert seen["count"] == 2 and not seen["failed"]
    assert seen["packages"][0] == {"name": "linux", "from": "7.2.14-1", "to": "7.2.15-1"}

    # Nothing to update is an answer, not a failure.
    answer.write_text("")
    seen = check(shell)
    assert seen["count"] == 0 and seen["packages"] == [] and not seen["failed"]

    # No answer leaves what was known, and says so.
    answer.write_text("kitty 0.40-1 -> 0.41-1\n")
    check(shell)
    answer.unlink()
    seen = check(shell)
    assert seen["failed"], "a check that got no answer read as an answer"
    assert seen["count"] == 1, "a check that got no answer changed the count"
