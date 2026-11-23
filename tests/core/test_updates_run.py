"""The update run by the shell: a service of its own, whose log the shell reads.

Its last step copies the shell's files and reloads the shell, so what the
shell knows of it is read from the log and the service. systemd is stood in
for, and nothing of the real update runs.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

FAKES = Path(__file__).resolve().parent / "fakes/update-run"
PROBE = SHELL / "benchUpdatesRunProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services

// Written by tests/core/test_updates_run.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "runProbe"
        function ready(): bool {
            return Config.ready;
        }
        function known(): bool {
            return Updates.shellAvailable;
        }
        function update(): void {
            Updates.update();
        }
        function state(): string {
            return JSON.stringify({
                updating: Updates.updating, step: Updates.updateStep, number: Updates.updateStepNumber,
                detail: Updates.updateDetail, package: Updates.updatePackage, share: Updates.updateShare,
                outcome: Updates.updateOutcome, failed: Updates.updateFailedStep, lines: Updates.updateLog, notes: Updates.updateNotes
            });
        }
    }
}
"""


@pytest.fixture
def run(request, bench, tmp_path, monkeypatch):
    known = getattr(request, "param", "known") == "known"
    repo = tmp_path / "YukiUI"
    repo.mkdir()
    (repo / "setup").write_text('#!/bin/sh\nprintf "state\\tok\\nbehind\\t0\\n"\n')
    config = bench.config_home / "illogical-impulse"
    config.mkdir(parents=True, exist_ok=True)
    saved = {name: (config / name).read_text() if (config / name).exists() else None for name in ("config.json", "repository")}
    (config / "config.json").write_text(json.dumps({"panelFamily": "blueberry",
                                                    "updates": {"enableCheck": False, "checkShell": False, "aur": False}}))
    if known:
        (config / "repository").write_text(f"{repo}\n")
    else:
        (config / "repository").unlink(missing_ok=True)
    files = {name: tmp_path / name for name in ("says", "active", "args", "keeps", "refuses", "real")}
    for name, variable in (("says", "FAKE_SAYS"), ("active", "FAKE_ACTIVE"), ("args", "FAKE_RUN_ARGS"), ("keeps", "FAKE_KEEPS"),
                           ("refuses", "FAKE_REFUSES"), ("real", "FAKE_REAL")):
        monkeypatch.setenv(variable, str(files[name]))
    monkeypatch.setenv("PATH", f"{FAKES}:{os.environ['PATH']}")
    files["says"].write_text("")
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("runProbe", "ready"))
    try:
        shell.start()
        # Answered is not ready: before the config and the repository are read
        # an update goes to a terminal.
        wait_until(lambda: shell.call("runProbe", "ready") == "true" and shell.call("runProbe", "known") == ("true" if known else "false"),
                   timeout=15, what="the config and the repository to be read")
        yield shell, files
        assert not files["real"].exists(), "a real program was reached for: " + files["real"].read_text()
        assert not shell.errors(), "the shell reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()
        for name, text in saved.items():
            if text is None:
                (config / name).unlink(missing_ok=True)
            else:
                (config / name).write_text(text)


def state(shell) -> dict:
    return json.loads(shell.call("runProbe", "state"))


def test_its_steps_and_packages_are_followed_and_it_ends_done(run):
    shell, files = run
    files["keeps"].write_text("")
    files["says"].write_text("@yuki step 1 4 shell\nYukiUI is up to date.\n@yuki step 2 4 system\n"
                             "\x1b[1m(3/40) upgrading harfbuzz\x1b[0m\n")
    shell.call("runProbe", "update")
    seen = wait_until(lambda: (s := state(shell))["step"] == "system" and s["share"] > 0 and s, what="the second step")
    assert seen["updating"] and seen["number"] == 2
    assert seen["detail"] == "upgrading harfbuzz"
    assert seen["share"] == pytest.approx(3 / 40)
    log = next(arg.split(":", 1)[1] for arg in files["args"].read_text().split() if arg.startswith("StandardOutput=truncate:"))
    with open(log, "a") as handle:
        handle.write("@yuki done\n")
    seen = wait_until(lambda: (s := state(shell))["outcome"] and s, what="the update to end")
    assert (seen["updating"], seen["outcome"]) == (False, "done")


def test_a_download_meter_is_not_what_it_shows(run):
    shell, files = run
    files["keeps"].write_text("")
    files["says"].write_text("@yuki step 2 4 system\n==> Making package: lib32-libtirpc 1.3.8-2 (Mon)\n==> Retrieving sources...\n"
                             "  -> Downloading libtirpc-1.3.8.tar.bz2...\n"
                             "  % Total    % Received % Xferd  Average Speed\n"
                             "  0      0   0      0   0      0      0      0\r100    388 100    388   0      0    917      0\r100    533 100    533\n")
    shell.call("runProbe", "update")
    seen = wait_until(lambda: (s := state(shell))["detail"].startswith("Downloading") and s, what="the download to be told")
    assert seen["detail"] == "Downloading libtirpc-1.3.8.tar.bz2..."
    assert seen["package"] == "lib32-libtirpc"
    assert seen["notes"] == ["Building lib32-libtirpc"]
    assert not [line for line in seen["lines"] if "533" in line or "% Total" in line], seen["lines"]
    # A build that counts its steps is told as a share.
    log = next(arg.split(":", 1)[1] for arg in files["args"].read_text().split() if arg.startswith("StandardOutput=truncate:"))
    with open(log, "a") as handle:
        handle.write("[ 25/100] Building CXX object src/a.o\n")
    wait_until(lambda: state(shell)["share"] == pytest.approx(0.25), what="the build's share")
    # What pacman does afterwards is not told under the name of what was built.
    with open(log, "a") as handle:
        handle.write("(2/9) upgrading openexr\n")
    wait_until(lambda: (s := state(shell))["detail"] == "upgrading openexr" and s["package"] == "", what="pacman's own step")


def test_where_it_stopped_is_told(run):
    shell, files = run
    files["says"].write_text("@yuki step 2 4 system\nerror: conflicting files\n@yuki failed system\n")
    shell.call("runProbe", "update")
    seen = wait_until(lambda: (s := state(shell))["outcome"] and s, what="the update to stop")
    assert (seen["outcome"], seen["failed"]) == ("failed", "system")
    assert "error: conflicting files" in seen["lines"]


def test_a_service_gone_without_a_word_is_not_left_running(run):
    shell, files = run
    files["says"].write_text("@yuki step 3 4 packages\n")
    shell.call("runProbe", "update")
    seen = wait_until(lambda: (s := state(shell))["outcome"] and s, timeout=20, what="the update to be noticed gone")
    assert (seen["outcome"], seen["failed"]) == ("failed", "packages")


def test_it_is_asked_for_as_its_own_service(run):
    shell, files = run
    shell.call("runProbe", "update")
    wait_until(lambda: files["args"].exists(), what="the service to be started")
    args = files["args"].read_text()
    assert "--unit=yuki-update" in args and "update --unattended" in args and "--no-aur" in args


@pytest.mark.parametrize("run", ["unknown"], indirect=True)
def test_not_knowing_where_yukiui_came_from_the_packages_are_upgraded_all_the_same(run):
    shell, files = run
    files["says"].write_text("@yuki step 1 1 system\n@yuki done\n")
    shell.call("runProbe", "update")
    seen = wait_until(lambda: (s := state(shell))["outcome"] and s, what="the update to end")
    assert seen["outcome"] == "done"
    args = files["args"].read_text()
    assert "update-packages.sh --service --unattended --no-aur" in args


def packages(tmp_path, *args, status=0):
    """The script alone, with a yay that says what it was asked and ends as told."""
    import subprocess
    bin = tmp_path / "bin"
    bin.mkdir()
    for name, body in (("pacman", "exit 0"), ("sudo", "exit 1"), ("yay", f'echo "yay $*"; exit {status}')):
        (bin / name).write_text(f"#!/bin/sh\n{body}\n")
        (bin / name).chmod(0o755)
    script = SHELL / "scripts/system/update-packages.sh"
    return subprocess.run(["bash", str(script), *args], capture_output=True, text=True, timeout=30,
                          env={"PATH": f"{bin}:/usr/bin:/bin"}, stdin=subprocess.DEVNULL)


def test_the_package_script_says_how_it_ended(tmp_path):
    ended = packages(tmp_path, "--service", "--unattended")
    assert ended.returncode == 0
    assert ended.stdout.splitlines()[0] == "@yuki step 1 1 system"
    assert ended.stdout.splitlines()[-1] == "@yuki done"
    assert "--noconfirm" in ended.stdout
    # sudo asks for a password here, so polkit's prompt is used.
    assert "--sudo pkexec" in ended.stdout


def test_the_package_script_fails_out_loud(tmp_path):
    ended = packages(tmp_path, "--service", "--unattended", "--no-aur", status=1)
    assert ended.returncode != 0
    assert ended.stdout.splitlines()[-1] == "@yuki failed system"
    assert "--repo" in ended.stdout
