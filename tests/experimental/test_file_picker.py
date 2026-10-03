"""The file picker the portal opens, answering through its fifo.

The selection is kept by url, and the row the keys are on used to be kept by
number. A folder whose listing changed under it, a download finishing say,
moved another file into that row, and Enter answered with that file.
"""

import json
import os
import threading
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell
from bench.windows import Keyboard

PROBE = SHELL / "benchFilePickerProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.experimental.filePicker

// Written by tests/experimental/test_file_picker.py for a test run, and removed after it.
ShellRoot {
    ExFilePicker {}
}
"""


@pytest.fixture(scope="module")
def picker_shell(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("filePicker", "pending", "none"))
    try:
        shell.start()
        yield shell
    finally:
        shell.call("filePicker", "close")
        shell.stop()
        shell.remove_probe()


class Answer:
    """What the picker writes into its fifo, read on a thread of its own: the
    picker opens the fifo only once it answers."""

    def __init__(self, fifo):
        self.text = None
        os.mkfifo(fifo)
        self.thread = threading.Thread(target=self._read, args=(fifo,), daemon=True)
        self.thread.start()

    def _read(self, fifo):
        with open(fifo) as reader:
            self.text = reader.read()

    def wait(self, timeout=5.0) -> dict:
        self.thread.join(timeout)
        assert self.text is not None, "the picker never answered"
        return json.loads(self.text) if self.text else {}


def open_picker(bench, shell, folder, fifo):
    shell.call("filePicker", "open", json.dumps({"mode": "open", "currentFolder": str(folder)}), str(fifo))
    picker = wait_until(lambda: next((c for c in bench.clients() if c["title"] == "File picker"), None),
                        what="the picker window")
    wait_until(lambda: any(c["address"] == picker["address"] and c["focusHistoryID"] == 0 for c in bench.clients()),
               what="the picker to have the keyboard")
    return picker


def test_enter_answers_the_file_selected_when_the_folder_changed(bench, picker_shell, tmp_path):
    folder = tmp_path / "files"
    folder.mkdir()
    for name in ("a.txt", "b.txt"):
        (folder / name).write_text(name)
    answer = Answer(tmp_path / "answer.fifo")
    open_picker(bench, picker_shell, folder, tmp_path / "answer.fifo")
    time.sleep(0.5)

    keyboard = Keyboard(bench)
    keyboard.type(*keyboard.tap("Down"))
    time.sleep(0.3)
    # Comes first by name, and every row moves down one.
    (folder / "0new.txt").write_text("new")
    time.sleep(1.5)
    keyboard.type(*keyboard.tap("Return"))

    uris = answer.wait().get("uris", [])
    assert [uri.rsplit("/", 1)[-1] for uri in uris] == ["a.txt"]
    assert not picker_shell.errors()
