"""The lock screen, on a compositor of its own.

A session lock taken by a test cannot be given back without a password, so
these tests do not share the bench the others run on.

The compositor draws the desktop under a lock surface wherever it is not
opaque. The desktop here is plain red, so any of it showing through is easy
to tell from the lock.
"""

import subprocess
import time

import pytest
from PIL import Image

from bench.bench import SHELL, Bench, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchLockProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import qs.experimental.lock

// Written by tests/experimental/test_lock.py for a test run, and removed after it.
ShellRoot {
    ExLock {}
}
"""


@pytest.fixture(scope="module")
def locked(tmp_path_factory):
    bench = Bench(tmp_path_factory.mktemp("lockbench"))
    bench.start()
    # Drawn under the lock as the live config draws it, see-through where the
    # lock surface is.
    bench.eval('hl.config({ misc = { force_default_wallpaper = 0, background_color = "rgb(ff0000)", session_lock_xray = true } })')
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("lock", "focus"))
    try:
        shell.start()
        shell.call("lock", "activate")
        yield bench, shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.stop()


def red_share(path) -> float:
    """How much of the red desktop is in a frame, 0 to 1: how far red stands
    above green and blue, on average. A lock surface half see-through over
    the desktop reads about a half."""
    image = Image.open(path).convert("RGB").resize((64, 36))
    pixels = list(image.get_flattened_data())
    return sum(max(0, r - max(g, b)) for r, g, b in pixels) / (255 * len(pixels))


def capture(bench, output, path) -> bool:
    return subprocess.run(["grim", "-o", output, str(path)], env=bench.environment(),
                          capture_output=True).returncode == 0


def test_desktop_is_red(locked, tmp_path):
    # What the other tests rely on: a screen with nothing over it is red. Read
    # off the compositor's own frame of a screen added while locked, before the
    # lock has a surface there.
    bench, _ = locked
    bench.hyprctl("output", "create", "headless", "BARE")
    try:
        reds = []
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            shot = tmp_path / f"bare-{len(reds):03d}.png"
            if capture(bench, "BARE", shot):
                reds.append(red_share(shot))
        assert reds and max(reds) > 0.9, f"the bare desktop never read as red: {reds}"
    finally:
        bench.hyprctl("output", "remove", "BARE")


def test_screen_added_while_locked_never_shows_the_desktop(locked, tmp_path):
    bench, _ = locked
    time.sleep(1.0)
    bench.hyprctl("output", "create", "headless", "LATE")
    try:
        frames = []
        deadline = time.monotonic() + 1.2
        while time.monotonic() < deadline:
            shot = tmp_path / f"late-{len(frames):03d}.png"
            if capture(bench, "LATE", shot):
                frames.append((time.monotonic(), shot))
        shares = [red_share(shot) for _, shot in frames]
        # The compositor's own frames of the screen, before the lock has a
        # surface there, are its business. From the lock's first frame on,
        # nothing of the desktop may show.
        first = next((i for i, share in enumerate(shares) if share < 0.95), None)
        assert first is not None, "the lock never drew on the new screen"
        assert max(shares[first:]) < 0.05, f"the desktop showed through the lock on the new screen: {shares}"
    finally:
        bench.hyprctl("output", "remove", "LATE")
