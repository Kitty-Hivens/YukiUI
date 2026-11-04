"""The lists of audio nodes follow the graph, a moment after it changes.

They are handed on a turn of the event loop later because a node going away
changes them from inside its own destructor, and a Repeater rebuilt there ended
the process. This does not bring that crash about, which was only ever seen on
a real card: it holds the lists to following the graph all the same.

A PipeWire of its own, so nothing here touches the person's sound.
"""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

from bench.bench import SHELL, ends_with_the_run, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchAudioListsProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_audio_lists.py for a test run, and removed after it.
ShellRoot {
    Repeater {
        id: streams
        model: Audio.outputAppNodes
        Item {
            required property var modelData
        }
    }
    IpcHandler {
        target: "audioProbe"
        function ready(): bool {
            return true;
        }
        function counts(): string {
            return JSON.stringify({ streams: Audio.outputAppNodes.length, devices: Audio.outputDevices.length, shown: streams.count });
        }
    }
}
"""


@pytest.fixture
def private_pipewire(monkeypatch):
    # Short: the path of its socket has a limit the bench's folders run past.
    folder = Path(tempfile.mkdtemp(prefix="bpw", dir=os.environ["XDG_RUNTIME_DIR"]))
    monkeypatch.setenv("PIPEWIRE_RUNTIME_DIR", str(folder))
    monkeypatch.setenv("PULSE_SERVER", "unix:/nonexistent")
    server = subprocess.Popen(["pipewire"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=ends_with_the_run)
    try:
        wait_until(lambda: (folder / "pipewire-0").exists(), what="a PipeWire of its own")
        yield
    finally:
        server.terminate()
        server.wait(timeout=5)
        shutil.rmtree(folder, ignore_errors=True)


def make(name: str, media_class: str):
    subprocess.run(["pw-cli", "create-node", "adapter",
                    f"factory.name=support.null-audio-sink media.class={media_class} node.name={name} object.linger=1 audio.position=[FL,FR]"],
                   check=True, capture_output=True)


def destroy(name: str):
    dump = json.loads(subprocess.run(["pw-dump"], check=True, capture_output=True, text=True).stdout)
    node = next(o["id"] for o in dump if o.get("type") == "PipeWire:Interface:Node" and o["info"]["props"].get("node.name") == name)
    subprocess.run(["pw-cli", "destroy", str(node)], check=True, capture_output=True)


def test_the_lists_follow_the_graph(bench, private_pipewire):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("audioProbe", "ready"))
    shell.start()
    try:
        counts = lambda: json.loads(shell.call("audioProbe", "counts"))
        make("alsa_output.bench", "Audio/Sink")
        make("app.stay", "Stream/Output/Audio")
        wait_until(lambda: counts() == {"streams": 1, "devices": 1, "shown": 1}, what="a device and a stream listed")
        for _ in range(4):
            make("app.brief", "Stream/Output/Audio")
            wait_until(lambda: counts()["shown"] == 2, what="the brief stream listed")
            destroy("app.brief")
            wait_until(lambda: counts()["shown"] == 1, what="the brief stream gone")
        assert shell.process.poll() is None
        assert not shell.errors()
    finally:
        shell.stop()
        shell.remove_probe()
