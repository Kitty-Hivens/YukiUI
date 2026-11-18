"""`./setup update`: what it says of a repository, and what it does with one.

Run on a repository of its own made for each test: the installer's files as
they stand in this working copy, committed, cloned, and the clone given a
remote of its own on the disk, so nothing reaches the network and this working
copy is not touched. The system's package manager is kept off the PATH, so the
steps that would upgrade or build packages say this is not Arch and pass, and
the copying step is replaced in the clone by one that only says it ran: the
real one writes into the person's session.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from bench.bench import SHELL

REPO = SHELL.parents[3]
HIDDEN = {"pacman", "yay", "paru", "makepkg"}
FILES_STUB = 'printf "files step ran with %s\\n" "$*"\n'


def git(cwd: Path, *args: str) -> str:
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    return subprocess.run(["git", "-C", str(cwd), *args], env=env, check=True, capture_output=True, text=True).stdout.strip()


def commit(cwd: Path, path: str, text: str, subject: str):
    (cwd / path).write_text(text)
    git(cwd, "add", path)
    git(cwd, "commit", "-q", "-m", subject)


@pytest.fixture
def world(tmp_path):
    """The installer committed in an upstream repository, a bare remote of it, and a clone of that."""
    upstream = tmp_path / "upstream"
    upstream.mkdir()
    listed = subprocess.run(["git", "-C", str(REPO), "ls-files", "--cached", "--others", "--exclude-standard", "-z", "setup", "sdata"],
                            check=True, capture_output=True).stdout.decode().split("\0")
    for name in filter(None, listed):
        source = REPO / name
        if not source.is_file():
            continue
        target = upstream / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    (upstream / "sdata/subcmd-install/3.files.sh").write_text(FILES_STUB)
    git(upstream, "init", "-q", "-b", "main")
    git(upstream, "add", "-A")
    git(upstream, "commit", "-q", "-m", "installer")
    remote = tmp_path / "remote.git"
    subprocess.run(["git", "clone", "-q", "--bare", str(upstream), str(remote)], check=True)
    git(upstream, "remote", "add", "origin", str(remote))
    git(upstream, "fetch", "-q", "origin")
    git(upstream, "branch", "-q", "--set-upstream-to=origin/main", "main")
    clone = tmp_path / "clone"
    subprocess.run(["git", "clone", "-q", str(remote), str(clone)], check=True)

    # Every program on the PATH but the package managers.
    bin = tmp_path / "bin"
    bin.mkdir()
    for directory in os.environ["PATH"].split(":"):
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            if name in HIDDEN or (bin / name).exists():
                continue
            path = Path(directory) / name
            if path.is_file() and os.access(path, os.X_OK):
                (bin / name).symlink_to(path)

    home = tmp_path / "home"
    home.mkdir()
    env = {
        "PATH": str(bin),
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_RUNTIME_DIR": str(tmp_path / "runtime"),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
    }
    return {"upstream": upstream, "clone": clone, "env": env, "home": home}


def setup(world, *args: str) -> subprocess.CompletedProcess:
    # A command that fails asks whether to try again and takes no answer as
    # yes, so a failure would go round for ever without the timeout.
    return subprocess.run([str(world["clone"] / "setup"), "update", *args], env=world["env"], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=120)


def status(world) -> dict:
    result = setup(world, "--check")
    assert result.returncode == 0, result.stdout + result.stderr
    facts = {"commit": []}
    for line in result.stdout.splitlines():
        key, _, value = line.partition("\t")
        if key == "commit":
            facts["commit"].append(value)
        else:
            facts[key] = value
    return facts


def push(world, path: str, subject: str):
    commit(world["upstream"], path, subject + "\n", subject)
    git(world["upstream"], "push", "-q", "origin", "main")


def test_up_to_date(world):
    facts = status(world)
    assert facts["repository"] == str(world["clone"])
    assert (facts["branch"], facts["state"], facts["behind"], facts["ahead"]) == ("main", "ok", "0", "0")
    assert facts["commit"] == []


def test_new_commits_are_listed_newest_first(world):
    push(world, "one.txt", "First change")
    push(world, "two.txt", "Second change")
    facts = status(world)
    assert (facts["state"], facts["behind"]) == ("ok", "2")
    assert [line.split("\t")[1] for line in facts["commit"]] == ["Second change", "First change"]


def test_changes_not_committed_are_in_the_way(world):
    push(world, "one.txt", "First change")
    (world["clone"] / "setup").write_text((world["clone"] / "setup").read_text() + "\n# edited here\n")
    facts = status(world)
    assert (facts["state"], facts["behind"]) == ("dirty", "1")


def test_a_file_nobody_tracks_is_not_in_the_way(world):
    (world["clone"] / "notes.txt").write_text("mine\n")
    assert status(world)["state"] == "ok"


def test_both_moved_on(world):
    push(world, "one.txt", "Upstream change")
    commit(world["clone"], "local.txt", "local\n", "Local change")
    facts = status(world)
    assert (facts["state"], facts["behind"], facts["ahead"]) == ("diverged", "1", "1")


def test_not_on_a_branch(world):
    git(world["clone"], "checkout", "-q", "--detach")
    assert status(world)["state"] == "detached"


def test_a_branch_that_follows_nothing(world):
    git(world["clone"], "checkout", "-q", "-b", "mine")
    assert status(world)["state"] == "no-upstream"


def test_a_remote_that_cannot_be_reached_keeps_the_last_count(world):
    push(world, "one.txt", "First change")
    git(world["clone"], "fetch", "-q")
    git(world["clone"], "remote", "set-url", "origin", str(world["clone"].parent / "gone.git"))
    facts = status(world)
    assert (facts["state"], facts["behind"]) == ("unreachable", "1")


def test_an_update_pulls_and_goes_on_with_the_new_version(world):
    # The new version says so as it starts, which only the new version can.
    run_script = "sdata/subcmd-update/0.run.sh"
    upstream_run = world["upstream"] / run_script
    upstream_run.write_text('printf "new updater from %s\\n" "$UPDATE_CONTINUE_FROM"\n' + upstream_run.read_text())
    git(world["upstream"], "commit", "-q", "-am", "A new updater")
    git(world["upstream"], "push", "-q", "origin", "main")
    before = git(world["clone"], "rev-parse", "HEAD")

    result = setup(world, "--no-system")
    out = result.stdout + result.stderr
    assert result.returncode == 0, out
    assert git(world["clone"], "rev-parse", "HEAD") == git(world["upstream"], "rev-parse", "HEAD")
    assert f"new updater from {before}" in out, out
    assert "files step ran" in out, out
    assert "not an Arch system" not in out, "the system step ran though it was asked not to"
    assert (world["home"] / ".local/state/yuki/updated").is_file()


def test_an_update_with_nothing_to_pull_copies_nothing(world):
    result = setup(world)
    out = result.stdout + result.stderr
    assert result.returncode == 0, out
    assert "YukiUI is up to date" in out
    assert "not an Arch system" in out
    assert "files step ran" not in out
    assert (world["home"] / ".local/state/yuki/updated").is_file()


def test_an_update_leaves_changes_not_committed_alone(world):
    push(world, "one.txt", "First change")
    edited = (world["clone"] / "setup").read_text() + "\n# edited here\n"
    (world["clone"] / "setup").write_text(edited)
    before = git(world["clone"], "rev-parse", "HEAD")

    result = setup(world, "--no-system")
    out = result.stdout + result.stderr
    assert result.returncode == 0, out
    assert git(world["clone"], "rev-parse", "HEAD") == before
    assert (world["clone"] / "setup").read_text() == edited
    assert "not committed" in out
    assert "files step ran" not in out
