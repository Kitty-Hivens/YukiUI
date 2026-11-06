"""What the clipboard history keeps, with wl-paste played by a stand-in.

Copying a photo froze Telegram for as long as it took to encode it, and it encoded
it once for every request: the picture wl-paste had just handed over was thrown
away and asked for again.
"""

import importlib.util
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest

from bench.bench import SHELL

HISTORY = SHELL / "scripts/clipboard/history.py"
PNG = b"\x89PNG\r\n\x1a\n" + b"picture" * 100

FAKE = """#!/bin/sh
# Writes down each request, and answers as a Qt program copying a picture does.
printf '%s\\n' "$*" >> "$FAKE_LOG"
case "$*" in
    *--list-types*) printf 'application/x-qt-image\\nimage/png\\nimage/bmp\\n' ;;
    *image/bmp*) printf 'BMbitmap' ;;
esac
"""


@pytest.fixture
def stand_in(tmp_path, monkeypatch):
    folder = tmp_path / "bin"
    folder.mkdir()
    fake = folder / "wl-paste"
    fake.write_text(FAKE)
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    environment = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}", FAKE_LOG=str(tmp_path / "log"),
                       XDG_STATE_HOME=str(tmp_path / "state"), CLIPBOARD_STATE="data")
    return environment, tmp_path


def store(environment, handed: bytes):
    subprocess.run(["python3", str(HISTORY), "store"], input=handed, env=environment, check=True)


def index(tmp_path) -> list:
    return json.loads((tmp_path / "state/yuki/clipboard/index.json").read_text())


def test_a_picture_handed_over_is_not_asked_for_again(stand_in):
    environment, tmp_path = stand_in
    store(environment, PNG)
    requests = (tmp_path / "log").read_text()
    assert "image/png" not in requests, f"asked for the picture again: {requests}"
    newest = index(tmp_path)[0]
    assert newest["kind"] == "image"
    assert Path(newest["image"]).read_bytes() == PNG
    assert newest["size"] == len(PNG)


def test_something_else_handed_over_is_not_taken_for_the_picture(stand_in):
    environment, tmp_path = stand_in
    store(environment, b"not a picture")
    assert "--type image/png" in (tmp_path / "log").read_text()


@pytest.fixture
def module(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    spec = importlib.util.spec_from_file_location("history_under_test", HISTORY)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    os.makedirs(loaded.FOLDER)
    return loaded


def made(module, name: str, size: int, pinned=False) -> dict:
    folder = Path(module.entry_folder(name))
    folder.mkdir()
    (folder / "form-0").write_bytes(b"x" * size)
    return {"id": name, "pinned": pinned, "size": size, "forms": [{"type": "text/plain", "file": str(folder / "form-0")}]}


def test_only_so_many_are_kept_and_pinned_ones_stay(module):
    module.LIMIT = 2
    entries = [made(module, str(n), 1, pinned=n == 3) for n in range(1, 5)]
    assert [entry["id"] for entry in module.prune(entries)] == ["1", "2", "3"]
    assert not Path(module.entry_folder("4")).exists()
    assert Path(module.entry_folder("3")).exists()


def test_the_oldest_go_once_all_together_is_past_the_limit(module):
    module.ALL_TOGETHER = 100
    entries = [made(module, str(n), 60) for n in range(1, 4)]
    assert [entry["id"] for entry in module.prune(entries)] == ["1"]
