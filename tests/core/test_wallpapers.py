"""The wallpaper service, going to a folder named by whoever made it.

The path of a folder was spliced into the shell script that checks it, so a
folder named with a quote ran whatever followed. A folder name cannot hold a
slash, so the one here writes its mark through a variable that names the
bench's own cache folder.
"""

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchWallpapersProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.core.functions

// Written by tests/core/test_wallpapers.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "wallpapersProbe"
        function ready(): string {
            Wallpapers.load();
            return "yes";
        }
        function go(path: string): void {
            Wallpapers.setDirectory(path);
        }
        function directory(): string {
            return decodeURIComponent(FileUtils.trimFileProtocol(Wallpapers.directory.toString()));
        }
    }
}
"""

NAME = 'x"; touch "$XDG_CACHE_HOME"pwned; "'


@pytest.fixture
def wallpapers(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("wallpapersProbe", "ready"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def test_a_folder_named_to_run_something_runs_nothing(bench, wallpapers, tmp_path):
    folder = tmp_path / NAME
    folder.mkdir()
    mark = bench.root / "cachepwned"
    wallpapers.call("wallpapersProbe", "go", str(folder))
    wait_until(lambda: wallpapers.call("wallpapersProbe", "directory") == str(folder), what="the service to go to the folder")
    assert not mark.exists(), "the folder's name ran as a command"
