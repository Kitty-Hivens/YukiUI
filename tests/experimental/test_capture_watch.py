"""Who is capturing, and the dock's marks for it.

What a stream is doing is read from what it is and what it takes from. The
shell's own screen recording is told by the recorder's note of its process,
here a stand in for the recorder kept in the bench's own runtime folder.
"""

import json
import signal
import subprocess
import time

import pytest

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchCaptureWatchProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.dock

// Written by tests/experimental/test_capture_watch.py for a test run, and removed after it.
ShellRoot {
    id: probe
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.experimental.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.experimental.dock.edge = "bottom";
    }
    ExDock {
        id: dock
    }

    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }

    IpcHandler {
        target: "captureProbe"
        function ready(): bool {
            return Config.ready;
        }
        function kind(mediaClass: string, binary: string, nodeName: string, linked: bool, fromOutput: bool, fromScreen: bool): string {
            return CaptureWatch.kindOf(mediaClass, binary, nodeName, linked, fromOutput, fromScreen);
        }
        function recheck(): void {
            CaptureWatch.recheck();
        }
        function recording(): bool {
            return CaptureWatch.recording;
        }
        function pidFile(): string {
            return CaptureWatch.pidFile;
        }
        function marksShown(): bool {
            const status = probe.find(dock.docks[0]?.contentItem, item => item.captureButton !== undefined);
            return status?.captureButton?.visible ?? false;
        }
        function openMenu(): void {
            dock.docks[0].toggleCaptureMenu();
        }
        function stop(): void {
            CaptureWatch.stopRecording();
        }
        function users(): string {
            return JSON.stringify(CaptureWatch.users);
        }
    }
}
"""


@pytest.fixture
def watch(bench):
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("captureProbe", "ready"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def kind(shell, media_class, linked=True, from_output=False, from_screen=False, binary="firefox", node="Firefox"):
    flag = lambda value: "true" if value else "false"
    return shell.call("captureProbe", "kind", media_class, binary, node, flag(linked), flag(from_output), flag(from_screen))


def test_what_a_stream_is_doing(watch):
    assert kind(watch, "Stream/Input/Audio") == "microphone"
    assert kind(watch, "Stream/Input/Audio", from_output=True) == "sound"
    assert kind(watch, "Stream/Input/Video") == "camera"
    assert kind(watch, "Stream/Input/Video", from_screen=True) == "screen"
    # Taking nothing yet, it is not capturing.
    assert kind(watch, "Stream/Input/Audio", linked=False) == ""
    # The shell's own streams and a processor in the way of every program.
    assert kind(watch, "Stream/Input/Audio", binary="quickshell") == ""
    assert kind(watch, "Stream/Input/Audio", node="easyeffects_source") == ""


def test_the_shells_recording_shows_on_the_dock_and_stops_from_it(bench, watch):
    pid_file = watch.call("captureProbe", "pidFile")
    assert pid_file.startswith(str(bench.runtime_dir)), "the note of the recorder is the session's"
    stand_in = subprocess.Popen(["sleep", "60"])
    try:
        with open(pid_file, "w") as note:
            note.write(f"{stand_in.pid}\n")
        watch.call("captureProbe", "recheck")
        wait_until(lambda: watch.call("captureProbe", "recording") == "true", what="the recording to be seen")
        wait_until(lambda: watch.call("captureProbe", "marksShown") == "true", what="the dock's marks to show")
        watch.call("captureProbe", "openMenu")
        time.sleep(0.5)
        watch.call("captureProbe", "stop")
        stand_in.wait(timeout=5)
        wait_until(lambda: watch.call("captureProbe", "recording") == "false", what="the recording to be seen stopped")
        wait_until(lambda: watch.call("captureProbe", "marksShown") == "false", what="the dock's marks to go")
        assert not watch.errors()
    finally:
        if stand_in.poll() is None:
            stand_in.kill()


def screen_takers(shell) -> list[str]:
    return [user["name"] for user in json.loads(shell.call("captureProbe", "users")) if user["kind"] == "screen"]


def test_a_program_taking_the_screen_from_the_compositor_is_named(bench, watch, tmp_path):
    # Named by the capture-report plugin, which the bench loads. A screenshot
    # takes the screen for a moment and is not shown at all.
    subprocess.run(["grim", "-o", OUTPUT, str(tmp_path / "shot.png")], env=bench.environment(), check=True)
    time.sleep(1.5)
    assert screen_takers(watch) == []

    recorder = subprocess.Popen(["wf-recorder", "-o", OUTPUT, "-f", str(tmp_path / "taken.mp4"), "-y"],
                                env=bench.environment(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_until(lambda: screen_takers(watch) == ["wf-recorder"], timeout=5, what="the recorder to be named")
    finally:
        recorder.send_signal(signal.SIGINT)
        try:
            recorder.wait(timeout=3)
        except subprocess.TimeoutExpired:
            recorder.kill()
            recorder.wait(timeout=5)
    wait_until(lambda: screen_takers(watch) == [], timeout=5, what="the recorder to go once it stopped")
