"""A config written before Blueberry was renamed comes up as Blueberry's.

Blueberry was called experimental, its id and its options with it. Read as it
stood, such a file came up on the fallback desktop with every Blueberry option
at its default, and the next write put the defaults over the old ones.
"""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchConfigMigrationProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Written by tests/core/test_config_migration.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "configProbe"
        function read(): string {
            if (!Config.ready)
                return "";
            return JSON.stringify({
                family: Config.options.panelFamily,
                disabled: Config.options.disabledEnvironments,
                style: Config.options.blueberry.dock.style,
                tiles: Config.options.blueberry.quickSettings.tiles
            });
        }
    }
}
"""


@pytest.fixture
def config_file(bench):
    path = bench.config_home / "illogical-impulse/config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    before = path.read_text() if path.exists() else None
    yield path
    if before is None:
        path.unlink(missing_ok=True)
    else:
        path.write_text(before)


def test_an_experimental_config_is_carried_over(bench, config_file):
    config_file.write_text(json.dumps({
        "panelFamily": "experimental",
        "disabledEnvironments": ["waffle", "experimental"],
        "experimental": {"dock": {"style": "island"}, "quickSettings": {"tiles": ["wifi", "gameMode"]}},
    }))
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("configProbe", "read"))
    try:
        shell.start()
        seen = json.loads(wait_until(lambda: shell.call("configProbe", "read"), what="the config to be read"))
    finally:
        shell.stop()
        shell.remove_probe()
    assert seen == {"family": "blueberry", "disabled": ["waffle", "blueberry"], "style": "island", "tiles": ["wifi", "gameMode"]}
    written = json.loads(config_file.read_text())
    assert "experimental" not in written
    assert written["blueberry"]["dock"]["style"] == "island"
    assert written["panelFamily"] == "blueberry"
