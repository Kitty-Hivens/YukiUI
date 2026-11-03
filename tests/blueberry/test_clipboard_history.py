"""The clipboard history on Win+V: what is kept, and what comes back.

On the bench's own clipboard and in its own state folder, so the person's
history is neither read nor written.
"""

import json
import subprocess
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchClipboardProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_clipboard_history.py for a test run, and removed after it.
ShellRoot {
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.blueberry.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        ExClipboardHistory.load();
        if (Config.ready)
            Config.options.blueberry.dock.edge = "bottom";
    }
    ExDock {}
    IpcHandler {
        target: "clipboardProbe"
        function ready(): bool {
            return Config.ready;
        }
    }
}
"""
OFFER = SHELL / "scripts/clipboard/offer.sh"
HISTORY = SHELL / "scripts/clipboard/history.py"


@pytest.fixture
def history(bench):
    folder = bench.state_home / "yuki/clipboard"
    subprocess.run(["rm", "-rf", "--", str(folder)], check=True)
    subprocess.run(["wl-copy", "--clear"], env=bench.environment(), check=True)
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("clipboardProbe", "ready"))
    try:
        shell.start()
        # The watcher is up once it has looked at the clipboard as it found it.
        time.sleep(1.0)
        yield shell
        assert not shell.errors(), "the history reported errors:\n" + "\n".join(shell.errors())
    finally:
        shell.stop()
        shell.remove_probe()


def entries(shell) -> list:
    return json.loads(shell.call("clipboardHistory", "entries"))


def kept(shell, count: int) -> list:
    return wait_until(lambda: (lambda e: e if len(e) >= count else None)(entries(shell)), what=f"{count} entries kept")


def types(bench) -> list:
    return subprocess.run(["wl-paste", "--list-types"], env=bench.environment(), capture_output=True, text=True).stdout.split()


def test_text_files_and_pictures_are_kept_with_their_forms(bench, history, tmp_path):
    env = bench.environment()
    subprocess.run(["wl-copy", "hello there"], env=env, check=True)
    kept(history, 1)
    (tmp_path / "a.txt").write_text("a")
    subprocess.run(["bash", str(OFFER), str(tmp_path / "a.txt")], env=env, check=True)
    kept(history, 2)
    picture = tmp_path / "p.png"
    subprocess.run(["magick", "-size", "40x30", "xc:red", str(picture)], check=True)
    subprocess.run(["bash", "-c", 'wl-copy --type image/png < "$1"', "copy", str(picture)], env=env, check=True)
    newest = kept(history, 3)
    assert [entry["kind"] for entry in newest] == ["image", "files", "text"]
    assert newest[2]["preview"] == "hello there"
    assert newest[1]["preview"] == "a.txt"
    assert {"text/uri-list", "x-special/gnome-copied-files"} <= set(newest[1]["forms"])


def test_a_secret_is_never_kept(bench, history):
    subprocess.run([str(bench.clip_tool), "-t", "text/plain", "hunter2", "-t", "x-kde-passwordManagerHint", "secret"],
                   env=bench.environment(), check=True)
    time.sleep(1.5)
    assert entries(history) == []
    assert not any((bench.state_home / "yuki/clipboard").glob("*/form-*"))


def test_a_file_chosen_goes_back_as_a_file_and_is_pasted(bench, desk, history, tmp_path):
    env = bench.environment()
    (tmp_path / "doc.txt").write_text("doc")
    subprocess.run(["bash", str(OFFER), str(tmp_path / "doc.txt")], env=env, check=True)
    kept(history, 1)
    subprocess.run(["wl-copy", "something else"], env=env, check=True)
    kept(history, 2)
    window = desk.wayland()
    window.wait(lambda c: desk.active() == c["address"], what="the window to have the keyboard")
    window.command("keys")
    history.call("clipboardHistory", "open")
    wait_until(lambda: history.call("clipboardHistory", "isOpen") == "true", what="the history to open")
    time.sleep(0.4)
    history.call("clipboardHistory", "choose", "1")
    # Back on in every form it was copied in, the files as files.
    wait_until(lambda: "x-special/gnome-copied-files" in types(bench), what="the files back on the clipboard")
    pressed = wait_until(lambda: window.command("keys")["keys"], what="the paste to reach the window")
    assert pressed[0] == ["pressed", "v", ["control"]]
    # And to the top of the history, not in it twice.
    newest = wait_until(lambda: (lambda e: e if e[0]["kind"] == "files" else None)(entries(history)), what="the file to come to the top")
    assert len(newest) == 2


def test_pinned_entries_outlive_clearing(bench, history):
    env = bench.environment()
    for text in ("one", "two"):
        subprocess.run(["wl-copy", text], env=env, check=True)
        kept(history, 1 if text == "one" else 2)
    first = entries(history)[1]
    subprocess.run(["python3", str(HISTORY), "pin", first["id"], "1"], env=env, check=True)
    subprocess.run(["python3", str(HISTORY), "clear"], env=env, check=True)
    left = wait_until(lambda: (lambda e: e if len(e) == 1 else None)(entries(history)), what="only the pinned one left")
    assert left[0]["preview"] == "one" and left[0]["pinned"]
