"""The screen share picker stays on the screen it opened on.

Bound to the screen in focus, it followed the pointer to another screen,
taking the keyboard with it and building every live picture again there.
"""

import time

import pytest

from bench.bench import OUTPUT, SHELL, WIDTH, wait_until
from bench.shell import Shell
from bench.windows import Pointer

PROBE = SHELL / "benchScreenShareProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.experimental.screenShare

// Written by tests/experimental/test_screen_share_picker.py for a test run, and removed after it.
ShellRoot {
    ExScreenSharePicker {}
}
"""


@pytest.fixture
def picker(bench, tmp_path):
    bench.hyprctl("output", "create", "headless", "SECOND")
    wait_until(lambda: any(m["name"] == "SECOND" for m in bench.monitors()), what="a second screen")
    bench.eval(f'hl.monitor({{ output = "SECOND", mode = "1280x720@60", position = "{WIDTH}x0", scale = 1 }})')
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("screenShare", "close"))
    pointer = Pointer(bench)
    try:
        shell.start()
        yield shell, pointer, tmp_path / "answer"
    finally:
        shell.call("screenShare", "close")
        pointer.close()
        shell.stop()
        shell.remove_probe()
        bench.hyprctl("output", "remove", "SECOND")
        bench.focus_output()


def picker_on(bench) -> str:
    for name, monitor in bench.json("layers").items():
        for layers in monitor["levels"].values():
            if any(layer["namespace"] == "quickshell:screenSharePicker" for layer in layers):
                return name
    return ""


def test_picker_stays_on_the_screen_it_opened_on(bench, picker):
    shell, pointer, answer = picker
    pointer.move(400, 400)
    wait_until(lambda: bench.json("activeworkspace").get("monitor") == OUTPUT, what="the first screen in focus")
    shell.call("screenShare", "open", "0", str(answer), "")
    wait_until(lambda: picker_on(bench) == OUTPUT, what="the picker on the first screen")
    pointer.glide(WIDTH + 400, 300)
    time.sleep(1.0)
    assert picker_on(bench) == OUTPUT
