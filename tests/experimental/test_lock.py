"""The lock screen, each test on a compositor of its own.

A session lock taken by a test cannot be given back without a password, so
these tests share neither the bench the others run on nor one another's.

The compositor draws the desktop under a lock surface wherever it is not
opaque, as the live config has it. The desktop here is plain red, so any of
it showing through is easy to tell from the lock.
"""

import subprocess
import time

import pytest
from PIL import Image

from bench.bench import OUTPUT, SHELL, Bench, wait_until
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


@pytest.fixture
def lockable(tmp_path_factory):
    bench = Bench(tmp_path_factory.mktemp("lockbench"))
    bench.start()
    bench.eval('hl.config({ misc = { force_default_wallpaper = 0, background_color = "rgb(ff0000)", session_lock_xray = true } })')
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("lock", "focus"))
    try:
        shell.start()
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


def film(bench, output, folder, seconds: float) -> list[float]:
    """The red share of every frame of an output captured over a while."""
    shares = []
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        shot = folder / f"{output}-{len(shares):03d}.png"
        if subprocess.run(["grim", "-o", output, str(shot)], env=bench.environment(),
                          capture_output=True).returncode == 0:
            shares.append(red_share(shot))
    return shares


def from_the_lock_on(shares: list[float]) -> list[float]:
    """The frames from the lock's first one on. Those before it are the
    desktop, or the compositor's own frame of a screen the lock has not
    reached yet."""
    first = next((i for i, share in enumerate(shares) if share < 0.95), None)
    assert first is not None, f"the lock never drew: {shares}"
    return shares[first:]


def test_desktop_reads_red(lockable, tmp_path):
    bench, _ = lockable
    shares = film(bench, OUTPUT, tmp_path, 0.3)
    assert shares and min(shares) > 0.9, f"the bare desktop did not read as red: {shares}"


def test_lock_fades_in_over_the_desktop(lockable, tmp_path):
    # Locked by hand, the lock comes up over the windows, as designed.
    bench, shell = lockable
    shell.call("lock", "activate")
    shares = from_the_lock_on(film(bench, OUTPUT, tmp_path, 1.0))
    assert any(0.05 < share < 0.95 for share in shares), f"the lock did not fade in: {shares}"
    assert shares[-1] < 0.05, f"the lock at rest lets the desktop through: {shares}"


def test_lock_before_sleep_is_whole_from_its_first_frame(lockable, tmp_path):
    # The compositor counts the session locked on the lock's first frame,
    # and the idle daemon lets the machine sleep on that.
    bench, _ = lockable
    bench.eval('hl.dispatch(hl.dsp.global("quickshell:lockNow"))')
    shares = from_the_lock_on(film(bench, OUTPUT, tmp_path, 1.0))
    assert max(shares) < 0.05, f"the desktop showed through the lock: {shares}"


def test_screen_added_while_locked_never_shows_the_desktop(lockable, tmp_path):
    bench, shell = lockable
    shell.call("lock", "activate")
    wait_until(lambda: film(bench, OUTPUT, tmp_path, 0.1)[-1] < 0.05, what="the lock to be up")
    time.sleep(0.5)
    bench.hyprctl("output", "create", "headless", "LATE")
    try:
        shares = from_the_lock_on(film(bench, "LATE", tmp_path, 1.2))
        assert max(shares) < 0.05, f"the desktop showed through the lock on the new screen: {shares}"
    finally:
        bench.hyprctl("output", "remove", "LATE")
