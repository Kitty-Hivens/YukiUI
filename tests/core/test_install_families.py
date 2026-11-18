"""Which desktops the installer puts on a machine, and that one alone stands.

A fresh install gets Blueberry and nothing else, an existing one keeps what it
has, and --families names the rest. Everything a desktop owns is left out of
the copy of the shell's tree when it is not selected, and taken off a machine
that had it. The last test copies the tree the way the installer does, with
Illogical Impulse and Waffle left out, and builds Blueberry from that copy on
the bench: a type of theirs reached from shared code would not resolve there.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

from bench.bench import SHELL, ends_with_the_run, wait_until
from bench.shell import Shell

REPO = SHELL.parents[3]
LIB = REPO / "sdata/lib"
FILES_STEP = REPO / "sdata/subcmd-install/3.files.sh"
LEGACY_STEP = REPO / "sdata/subcmd-install/3.files-legacy.sh"


def run(script: str, config_home: Path, repo: Path = REPO, home: Path | None = None) -> subprocess.CompletedProcess:
    """The script under the installer's own conditions: its libraries, `set -e`, the repository as the directory."""
    env = {
        "PATH": os.environ["PATH"],
        "HOME": str(home or config_home.parent),
        "XDG_CONFIG_HOME": str(config_home),
        "XDG_DATA_HOME": str(config_home.parent / "data"),
        "REPO_ROOT": str(repo),
    }
    preamble = f'set -e\nsource "{LIB}/environment-variables.sh"\nsource "{LIB}/functions.sh"\nsource "{LIB}/families.sh"\n'
    # A failed command asks whether to repeat it and takes no answer as yes,
    # so a failure here would go round for ever without the timeout.
    return subprocess.run(["bash", "-c", preamble + script], env=env, cwd=repo, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=120)


def selected(result: subprocess.CompletedProcess) -> str:
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def install(config_home: Path, *ids: str):
    for id in ids:
        place = config_home / "quickshell/yuki/environments" / id
        place.mkdir(parents=True)
        (place / "manifest.json").write_text("{}")


def fake_repo(root: Path, manifests: dict[str, dict]) -> Path:
    for id, manifest in manifests.items():
        place = root / "dots/.config/quickshell/yuki/environments" / id
        place.mkdir(parents=True)
        (place / "manifest.json").write_text(json.dumps(manifest))
    return root


SHOW = 'echo "${FAMILIES_SELECTED[*]} ${FAMILIES_SELECTED_HOW}"'


def test_a_fresh_install_gets_blueberry_alone(tmp_path):
    assert selected(run(f'families_select "" false\n{SHOW}', tmp_path / "config")) == "blueberry default"


def test_an_install_keeps_the_desktops_it_has(tmp_path):
    config = tmp_path / "config"
    install(config, "ii", "waffle")
    assert selected(run(f'families_select "" false\n{SHOW}', config)) == "ii waffle kept"


@pytest.mark.parametrize("spec, expected", [
    ("ii", "ii asked"),
    ("ii, blueberry,ii", "ii blueberry asked"),
    ("all", "blueberry ii waffle asked"),
])
def test_the_desktops_asked_for(tmp_path, spec, expected):
    config = tmp_path / "config"
    # Asking outranks what is there.
    install(config, "waffle")
    assert selected(run(f'families_select "{spec}" true\n{SHOW}', config)) == expected


@pytest.mark.parametrize("spec", ["blueberry,nope", "", " , "])
def test_a_desktop_that_is_not_there_stops_the_run(tmp_path, spec):
    result = run(f'families_select "{spec}" true\necho went on', tmp_path / "config")
    assert result.returncode != 0
    assert "went on" not in result.stdout
    assert "blueberry ii waffle" in result.stderr, "the refusal does not say what can be installed"


def test_what_blueberry_alone_leaves_out(tmp_path):
    out = selected(run('families_select blueberry true\nfamilies_rsync_excludes /yuki', tmp_path / "config"))
    assert set(out.splitlines()) == {
        "/yuki/bench*Probe.qml",
        "/yuki/environments/ii",
        "/yuki/ii",
        "/yuki/systemSettings.qml",
        "/yuki/appearanceSettings.qml",
        "/yuki/welcome.qml",
        "/yuki/environments/waffle",
        "/yuki/waffle",
    }


def test_every_desktop_lists_only_files_that_are_there(tmp_path):
    # A name in a manifest that the tree does not hold is a rename that
    # missed the manifest, and the file under its new name would go to every
    # install whether its desktop was selected or not.
    out = selected(run('families_select all true\nfor id in $(families_available); do families_owned "$id"; done', tmp_path / "config"))
    missing = [path for path in out.splitlines() if not (SHELL / path).exists()]
    assert not missing, f"listed by a manifest and not in the tree: {missing}"


def test_a_file_two_desktops_claim_is_refused(tmp_path):
    repo = fake_repo(tmp_path / "repo", {"a": {"files": ["shared.qml"]}, "b": {"files": ["shared.qml"]}})
    result = run('families_select a true\nfamilies_excluded_paths', tmp_path / "config", repo=repo)
    assert result.returncode != 0
    assert "shared.qml" in result.stderr


@pytest.mark.parametrize("entry", ["../core", "/etc", "*.qml", "a/../b", "", "with space.qml", 3])
def test_a_file_outside_the_tree_or_a_pattern_is_refused(tmp_path, entry):
    repo = fake_repo(tmp_path / "repo", {"a": {}, "b": {"files": [entry]}})
    result = run('families_select a true\nfamilies_excluded_paths', tmp_path / "config", repo=repo)
    assert result.returncode != 0


def legacy_copy(config_home: Path, families: str) -> subprocess.CompletedProcess:
    """The legacy copying step with only the shell's tree copied, run with the
    helpers it calls taken from the step that defines them. That step also
    enables a user service, writes to ~/.local/bin and reloads the
    compositor, so it is not run whole."""
    helpers = ("warning_overwrite", "cp_file", "rsync_dir__sync_drop", "install_file", "install_dir__sync_drop")
    pattern = "|".join(helpers)
    script = (
        f'eval "$(awk \'/^(function )?({pattern})\\(\\)\\{{/,/^}}/\' "{FILES_STEP}")"\n'
        "ask=false\n"
        "SKIP_MISCCONF=true SKIP_FISH=true SKIP_FONTCONFIG=true SKIP_HYPRLAND=true\n"
        f'families_select "{families}" true\n'
        f'source "{LEGACY_STEP}"\n'
    )
    return run(script, config_home)


@pytest.fixture
def blueberry_alone(tmp_path):
    """A shell tree installed with ii and Waffle on it before, then installed again with Blueberry alone."""
    config = tmp_path / "config"
    first = legacy_copy(config, "all")
    assert first.returncode == 0, first.stdout + first.stderr
    tree = config / "quickshell/yuki"
    assert (tree / "ii").is_dir() and (tree / "environments/waffle/manifest.json").is_file()
    (tree / "benchSplitLeftoverProbe.qml").write_text("left behind by a test run\n")

    second = legacy_copy(config, "blueberry")
    assert second.returncode == 0, second.stdout + second.stderr
    return tree


def test_a_desktop_left_out_is_removed_and_the_rest_stays(blueberry_alone):
    tree = blueberry_alone
    for gone in ("ii", "waffle", "environments/ii", "environments/waffle",
                 "systemSettings.qml", "appearanceSettings.qml", "welcome.qml", "benchSplitLeftoverProbe.qml"):
        assert not (tree / gone).exists(), f"{gone} is still there"
    for kept in ("shell.qml", "core", "common", "plugins", "scripts/yukictl",
                 "blueberry", "environments/blueberry/manifest.json", "blueberrySettings.qml", "blueberryGallery.qml"):
        assert (tree / kept).exists(), f"{kept} went missing"


PROBE_SOURCE = """// The imports shell.qml has, the absent desktops' among them.
import "core"
import "common"
import "core/services"
import "environments/ii"
import "environments/waffle"
import "environments/blueberry"

import QtQuick
import Quickshell
import Quickshell.Io

// Written by tests/core/test_install_families.py into a copy of the tree.
ShellRoot {
    id: root

    // Built as far as a component goes and no further: every type the file
    // reaches is resolved, and nothing is made, so nothing starts.
    function compiled(file: string): string {
        const component = Qt.createComponent(Quickshell.shellPath(file), Component.PreferSynchronous);
        const result = component.status === Component.Ready ? "ready" : component.errorString();
        component.destroy();
        return result;
    }

    IpcHandler {
        target: "splitProbe"
        function state(): string {
            return JSON.stringify({
                environment: root.compiled("environments/blueberry/BlueberryEnvironment.qml"),
                ii: root.compiled("environments/ii/IiEnvironment.qml")
            });
        }
    }
}
"""


def test_blueberry_builds_from_a_tree_without_the_others(bench, blueberry_alone):
    shell = Shell(bench, probe=blueberry_alone / "splitProbe.qml", source=PROBE_SOURCE, ready=("splitProbe", "state"))
    shell.start()
    try:
        state = json.loads(shell.call("splitProbe", "state"))
        errors = shell.errors()
    finally:
        shell.stop()
        shell.remove_probe()
    assert state["environment"] == "ready", state["environment"]
    # What makes the one above worth anything: the copy really lacks ii.
    assert state["ii"] != "ready"
    assert not errors, "the shell reported errors:\n" + "\n".join(errors)


@pytest.mark.parametrize("root, title", [
    ("blueberrySettings.qml", "Blueberry Settings"),
    ("blueberryGallery.qml", "Blueberry Gallery"),
])
def test_blueberry_windows_open_from_a_tree_without_the_others(bench, blueberry_alone, tmp_path, root, title):
    # Each is a root of its own, started with `qs -p` as the shell and the
    # settings script start it, so the types it reaches are the ones a scan
    # from that file registers. Its own config folder: it writes the config
    # it reads, and the bench's is the other tests'.
    file = blueberry_alone / root
    # Taken only for where it logs and how it reads the log back.
    logs = Shell(bench, probe=file)
    env = bench.environment()
    env.update({"QT_QUICK_BACKEND": "software", "XDG_CONFIG_HOME": str(tmp_path / "own-config")})
    process = subprocess.Popen(["qs", "-p", str(file)], env=env, stdout=open(logs.log, "a"),
                               stderr=subprocess.STDOUT, preexec_fn=ends_with_the_run)
    try:
        def shown():
            if process.poll() is not None:
                raise AssertionError(f"{root} exited with {process.returncode}:\n" + "\n".join(logs.errors()))
            return any(c.get("title") == title for c in bench.clients())
        wait_until(shown, timeout=30, what=f"the {title} window")
        errors = logs.errors()
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
    assert not errors, f"{root} reported errors:\n" + "\n".join(errors)
