"""The clipboard history as the search of ii and Waffle reads it.

On the bench's own clipboard and state folder, so the person's history is neither
read nor written.
"""

import json
import subprocess

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchClipboardSearchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.common.widgets

// Written by tests/core/test_clipboard_search.py for a test run, and removed after it.
ShellRoot {
    Component.onCompleted: ClipboardHistory.load()
    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 200
        title: "clipboard search probe"
        ClipboardImage {
            id: image
            maxWidth: 100
            maxHeight: 100
        }
    }
    IpcHandler {
        target: "clipboardSearchProbe"
        function ready(): bool {
            return Config.ready;
        }
        function search(text: string): string {
            LauncherSearch.query = Config.options.search.prefix.clipboard + text;
            return JSON.stringify(LauncherSearch.results.map(result => ({ name: result.name, type: result.type, picture: result.clipboardImage, actions: result.actions.length })));
        }
        function run(index: int): void {
            LauncherSearch.results[index].execute();
        }
        function remove(index: int): void {
            LauncherSearch.results[index].actions[1].execute();
        }
        function wipe(): void {
            ClipboardHistory.wipe();
        }
        function setPicture(path: string): void {
            image.path = path;
        }
        function imageWidth(): real {
            return image.implicitWidth;
        }
    }
}
"""


@pytest.fixture
def probe(bench):
    subprocess.run(["rm", "-rf", "--", str(bench.state_home / "yuki/clipboard")], check=True)
    subprocess.run(["wl-copy", "--clear"], env=bench.environment(), check=True)
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("clipboardSearchProbe", "ready"))
    try:
        shell.start()
        yield shell
        assert not shell.errors(), "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def search(shell, text="") -> list:
    return json.loads(shell.call("clipboardSearchProbe", "search", text))


def test_text_and_a_picture_are_found_and_come_back(bench, probe, tmp_path):
    env = bench.environment()
    subprocess.run(["wl-copy", "first words"], env=env, check=True)
    wait_until(lambda: len(search(probe)) == 1, what="the text in the search")
    picture = tmp_path / "p.png"
    subprocess.run(["magick", "-size", "40x30", "xc:red", str(picture)], check=True)
    subprocess.run(["bash", "-c", 'wl-copy --type image/png < "$1"', "copy", str(picture)], env=env, check=True)
    found = wait_until(lambda: (lambda r: r if len(r) == 2 else None)(search(probe)), what="the picture in the search")
    assert found[0]["picture"] and found[0]["actions"] == 2
    assert found[1]["name"] == "first words" and not found[1]["picture"]

    # Drawn from where the history keeps it, at its own width.
    probe.call("clipboardSearchProbe", "setPicture", found[0]["picture"])
    wait_until(lambda: float(probe.call("clipboardSearchProbe", "imageWidth")) == 40, what="the picture to be drawn")

    # Searching finds by the words.
    assert [r["name"] for r in search(probe, "words")] == ["first words"]

    # Chosen, it goes back on the clipboard.
    search(probe)
    probe.call("clipboardSearchProbe", "run", "1")
    wait_until(lambda: subprocess.run(["wl-paste", "--no-newline"], env=env, capture_output=True).stdout == b"first words",
               what="the text back on the clipboard")


def test_deleting_and_wiping(bench, probe):
    env = bench.environment()
    for count, text in enumerate(("one", "two", "three"), start=1):
        subprocess.run(["wl-copy", text], env=env, check=True)
        wait_until(lambda: len(search(probe)) == count, what=f"{text} in the search")
    probe.call("clipboardSearchProbe", "remove", "0")
    wait_until(lambda: [r["name"] for r in search(probe)] == ["two", "one"], what="the entry to go")
    probe.call("clipboardSearchProbe", "wipe")
    wait_until(lambda: search(probe) == [], what="the history to be wiped")
