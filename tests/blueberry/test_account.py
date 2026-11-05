"""What the account page asks of the system, against a stand-in for the bus.

AccountsService refuses a picture over a megabyte, which is any photo, so a
picture is brought down first. A name goes across as one argument whatever is in
it.
"""

import json
import os
from pathlib import Path

import pytest
from PIL import Image

from bench.bench import SHELL, wait_until
from bench.shell import Shell

FAKES = Path(__file__).resolve().parent / "fakes/accounts"
PROBE = SHELL / "benchAccountProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.blueberry.looks
import qs.blueberry.settings

// Written by tests/blueberry/test_account.py for a test run, and removed after it.
ShellRoot {
    AccountLink {
        id: account
    }
    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 200
        title: "account probe"
        ExAvatar {
            id: avatar
            size: 72
            revision: account.pictureRevision
        }
    }
    IpcHandler {
        target: "accountProbe"
        function ready(): bool {
            return true;
        }
        function setName(name: string): void {
            account.setRealName(name);
        }
        function setPicture(path: string): void {
            account.setPicture(path);
        }
        function state(): string {
            return JSON.stringify({ busy: account.busy, failure: account.failure, revision: account.pictureRevision, picture: avatar.picture });
        }
    }
}
"""


@pytest.fixture
def account(bench, tmp_path, monkeypatch):
    bus = tmp_path / "bus"
    bus.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("PATH", f"{FAKES}:{os.environ['PATH']}")
    monkeypatch.setenv("FAKE_BUS", str(bus))
    monkeypatch.setenv("HOME", str(home))
    # Somebody with no picture in AccountsService's folder, whoever runs this.
    monkeypatch.setenv("USER", "bench-nobody")
    (home / ".face").write_bytes(b"")
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("accountProbe", "ready"))
    try:
        shell.start()
        yield shell, bus, home
    finally:
        shell.stop()
        shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("accountProbe", "state"))


def test_a_name_goes_across_whole(account):
    shell, bus, _ = account
    shell.call("accountProbe", "setName", 'Анна "Ли" $HOME')
    wait_until(lambda: (bus / "calls").exists(), what="the call")
    call = (bus / "calls").read_text()
    assert "SetRealName s" in call
    assert 'Анна "Ли" $HOME' in call, call


def test_a_photo_is_brought_down_before_it_is_handed_over(account, tmp_path):
    shell, bus, _ = account
    photo = tmp_path / "photo.png"
    Image.effect_noise((3000, 2000), 64).convert("RGB").save(photo)
    assert photo.stat().st_size > 1024 * 1024

    shell.call("accountProbe", "setPicture", str(photo))
    wait_until(lambda: state(shell)["revision"] == 1, timeout=30, what="the picture to be set")
    assert "SetIconFile s" in (bus / "calls").read_text()
    made = bus / "picture.png"
    assert made.stat().st_size < 1024 * 1024
    assert Image.open(made).size == (512, 512)


def test_a_refused_change_says_so(account, tmp_path):
    shell, bus, _ = account
    (bus / "refuse").touch()
    shell.call("accountProbe", "setName", "Кто-то")
    wait_until(lambda: state(shell)["failure"] != "", what="the refusal to be said")
    assert "refused" in state(shell)["failure"]


def test_a_face_file_is_the_picture_when_there_is_nothing_else(account):
    shell, bus, home = account
    assert state(shell)["picture"] == "", "an empty file was taken for a picture"
    Image.new("RGB", (64, 64), "#336699").save(home / ".face", "PNG")
    # Read again once a picture has been changed.
    shell.call("accountProbe", "setPicture", str(home / ".face"))
    wait_until(lambda: state(shell)["revision"] == 1, timeout=30, what="the picture to be set")
    wait_until(lambda: state(shell)["picture"] == str(home / ".face"), what="the avatar to find it")
