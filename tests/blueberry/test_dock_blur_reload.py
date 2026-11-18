"""The blur behind the dock across a reload of the compositor.

A reload builds every rule anew, and the dock's blur is a rule the shell asks
for, so after one the dock went unblurred until the shell heard of the reload
and asked again: the blur blinked whenever a config file changed. The shell
now writes down what it asked for, and the rules build it as they load.
"""

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDockBlurProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.core
import qs.blueberry.dock

// Written by tests/blueberry/test_dock_blur_reload.py for a test run, and removed after it.
ShellRoot {
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.blueberry.dock.blur = true;
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.blueberry.dock.blur = true;
    }
    ExDock {}
}
"""


@pytest.fixture
def dock(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("dock", "activate", "99"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def blur_rule(bench) -> bool:
    return bench.lua_value("YUKI_DOCK_BLUR_RULE ~= nil") == "true"


def test_the_dock_is_blurred_from_the_first_moment_after_a_reload(bench, dock):
    state = bench.state_home / "yuki/dock-blur"
    wait_until(lambda: state.exists() and state.read_text().startswith("1\t"), what="the blur written down")
    wait_until(lambda: blur_rule(bench), what="the blur asked for")
    # Stopped first, so nothing can ask for it again after the reload.
    dock.stop()
    bench.reload()
    assert blur_rule(bench), "the reload left the dock without its blur"
