"""The scratch folders the shell empties as it starts.

Emptied by a script the path was spliced into between single quotes, a path
holding a quote cut the rm short and ran the rest. The path now goes in as an
argument, and this checks the folders still come out empty and made.
"""

from pathlib import Path

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchDirectoriesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Written by tests/core/test_directories.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "directoriesProbe"
        function coverArt(): string {
            return Directories.coverArt;
        }
    }
}
"""


def test_scratch_folders_come_out_empty_and_made(bench):
    leftover = None
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("directoriesProbe", "coverArt"))
    try:
        shell.start()
        cover_art = shell.call("directoriesProbe", "coverArt")
        assert cover_art.startswith(str(bench.cache_home)), cover_art
        folder = Path(cover_art)
        wait_until(folder.is_dir, what="the cover art folder to be made")
        leftover = folder / "old.png"
        leftover.write_text("x")
    finally:
        shell.stop()
    # Started again, the shell empties it.
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("directoriesProbe", "coverArt"))
    try:
        shell.start()
        wait_until(lambda: leftover.parent.is_dir() and not leftover.exists(), what="the folder to be emptied and made again")
    finally:
        shell.stop()
        shell.remove_probe()
