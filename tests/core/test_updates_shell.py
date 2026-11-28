"""The shell asks YukiUI's repository whether it can be updated.

The installer writes down where it was installed from, and the shell runs
`setup update --check` there and reads its answer. As it comes up it reads
what the copy is and follows with --offline, which goes over no network.
Here the repository is a folder holding a `setup` that answers as the real
one does and counts how often it was asked, so nothing reaches the network. The system's packages are
not checked: that asks the mirrors.
"""

from __future__ import annotations

import json
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchUpdatesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services

// Written by tests/core/test_updates_shell.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "updatesProbe"
        function state(): string {
            return JSON.stringify({
                ready: Config.ready,
                repository: Updates.repository,
                state: Updates.shellState,
                behind: Updates.shellBehind,
                commits: Updates.shellCommits,
                pending: Updates.shellPending,
                channel: Updates.shellChannel,
                version: Updates.shellVersion,
                latest: Updates.shellLatest
            });
        }
        function setChannel(channel: string): void {
            Updates.setChannel(channel);
        }
    }
}
"""

ANSWER = ("repository\t{repo}\nchannel\tstable\nversion\t2026.11.28\t3\nlatest\t2026.11.28\nbranch\tmain\n"
          "state\t{state}\nbehind\t{behind}\nahead\t0\n{commits}")
# Answers as the real one does: a check counted, read offline not, and a
# channel set kept in a file of its own beside it, as git config keeps it.
SETUP = """#!/usr/bin/env bash
channel="$(cat "{channel}" 2> /dev/null || echo stable)"
args=("$@")
if [[ "${{args[1]}}" == "--channel" ]]; then
  echo "${{args[2]}}" > "{channel}"
  channel="${{args[2]}}"
  args=("${{args[0]}}" "${{args[@]:3}}")
fi
case "${{args[*]}}" in
  "update --check") echo . >> "{asked}" ;;
  "update --check --offline") echo . >> "{offline}" ;;
  *) exit 2 ;;
esac
awk -F'\\t' -v OFS='\\t' -v channel="$channel" '$1 == "channel" {{ $2 = channel }} {{ print }}' "{answer}"
"""


@pytest.fixture
def repository(bench, tmp_path):
    repo = tmp_path / "YukiUI"
    repo.mkdir()
    asked = tmp_path / "asked"
    offline = tmp_path / "offline"
    channel = tmp_path / "channel"
    answer = tmp_path / "answer"

    def answers(state="ok", behind=0, commits=()):
        lines = "".join(f"commit\t{hash}\t{subject}\n" for hash, subject in commits)
        answer.write_text(ANSWER.format(repo=repo, state=state, behind=behind, commits=lines))

    answers()
    (repo / "setup").write_text(SETUP.format(asked=asked, offline=offline, channel=channel, answer=answer))

    config = bench.config_home / "illogical-impulse"
    config.mkdir(parents=True, exist_ok=True)
    saved = {name: (config / name).read_text() if (config / name).exists() else None for name in ("config.json", "repository")}
    (config / "config.json").write_text(json.dumps({"panelFamily": "blueberry", "updates": {"enableCheck": False, "checkShell": True}}))
    (config / "repository").write_text(f"{repo}\n")
    stamp = bench.state_home / "yuki/updated"
    stamp.unlink(missing_ok=True)

    def times_asked() -> int:
        return len(asked.read_text().splitlines()) if asked.exists() else 0

    def times_read() -> int:
        return len(offline.read_text().splitlines()) if offline.exists() else 0

    yield {"answers": answers, "asked": times_asked, "read": times_read, "stamp": stamp, "repo": repo, "channel": channel}

    stamp.unlink(missing_ok=True)
    for name, text in saved.items():
        if text is None:
            (config / name).unlink(missing_ok=True)
        else:
            (config / name).write_text(text)


@pytest.fixture
def probe(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("updatesProbe", "state"))
    shell.start()
    yield shell
    shell.stop()
    shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("updatesProbe", "state"))


def test_new_commits_are_read(repository, probe):
    repository["answers"]("ok", 2, [("abc1234", "Second change"), ("def5678", "First change")])
    # The probe was up before the answer above was written, so it asks again
    # through the updater's stamp, as it does after an update.
    repository["stamp"].parent.mkdir(parents=True, exist_ok=True)
    repository["stamp"].write_text("1\n")
    seen = wait_until(lambda: (s := state(probe))["behind"] == 2 and s, timeout=15, what="the new commits to be read")
    assert seen["repository"] == str(repository["repo"])
    assert seen["state"] == "ok"
    assert seen["commits"] == [{"hash": "abc1234", "subject": "Second change"}, {"hash": "def5678", "subject": "First change"}]
    assert seen["pending"] is True


def test_asked_as_it_starts_and_again_after_an_update(repository, probe):
    wait_until(lambda: repository["asked"]() >= 1 and state(probe)["state"] == "ok", timeout=15, what="the first check")
    assert state(probe)["pending"] is False
    first = repository["asked"]()
    # The stamp did not exist when the shell came up.
    repository["stamp"].parent.mkdir(parents=True, exist_ok=True)
    repository["stamp"].write_text("1\n")
    wait_until(lambda: repository["asked"]() > first, timeout=15, what="a check after the update")


def test_changes_in_the_way_are_not_pending(repository, probe):
    repository["answers"]("dirty", 3, [("abc1234", "A change")])
    repository["stamp"].parent.mkdir(parents=True, exist_ok=True)
    repository["stamp"].write_text("1\n")
    seen = wait_until(lambda: (s := state(probe))["state"] == "dirty" and s, timeout=15, what="the repository to be read as dirty")
    assert seen["behind"] == 3
    assert seen["pending"] is False


def test_an_answer_that_is_not_one_leaves_the_last(repository, probe):
    wait_until(lambda: state(probe)["state"] == "ok", timeout=15, what="the first check")
    asked = repository["repo"].parent / "nonsense-asked"
    (repository["repo"] / "setup").write_text(f'#!/usr/bin/env bash\necho . >> "{asked}"\necho nonsense\n')
    repository["stamp"].parent.mkdir(parents=True, exist_ok=True)
    repository["stamp"].write_text("1\n")
    wait_until(lambda: asked.exists(), timeout=15, what="the repository to be asked again")
    # Its answer is read as the process ends, a moment after it wrote this.
    time.sleep(1)
    assert state(probe)["state"] == "ok"


@pytest.fixture
def unchecked(bench, repository):
    """Checking by itself switched off before the shell comes up."""
    config = bench.config_home / "illogical-impulse" / "config.json"
    config.write_text(json.dumps({"panelFamily": "blueberry", "updates": {"enableCheck": False, "checkShell": False}}))


def test_the_version_is_read_without_a_check(repository, unchecked, probe):
    seen = wait_until(lambda: (s := state(probe))["version"] and s, timeout=15, what="the version to be read")
    assert (seen["version"], seen["channel"], seen["latest"]) == ("2026.11.28+3", "stable", "2026.11.28")
    assert repository["read"]() >= 1
    # What the remote has is no part of it.
    assert (seen["state"], seen["behind"], repository["asked"]()) == ("", 0, 0)


def test_the_channel_is_set_through_the_updater(repository, probe):
    wait_until(lambda: state(probe)["channel"] == "stable", timeout=15, what="the channel to be read")
    probe.call("updatesProbe", "setChannel", "main")
    wait_until(lambda: repository["channel"].exists() and repository["channel"].read_text().strip() == "main",
               timeout=10, what="the updater to be told the channel")
    wait_until(lambda: state(probe)["channel"] == "main", timeout=10, what="the channel the updater answers with")
