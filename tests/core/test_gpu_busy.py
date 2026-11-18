"""How busy the graphics card is, from the kernel's accounts of each program.

Intel's drivers say only how fast the card runs, and the game bar showed that
clock against its top as the load, red at a fifth busy. The helper adds up
each program's time on each engine instead.
"""

import importlib.util
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "dots/.config/quickshell/yuki/scripts/system/gpu_busy.py"

spec = importlib.util.spec_from_file_location("gpu_busy", HELPER)
gpu_busy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu_busy)


def test_cycles_are_shared_out_over_every_client_and_every_engine_of_a_class():
    # xe: cycles on the engine against cycles that passed. Two clients on the
    # render engine, and a video class of two engines one of them half used.
    before = {
        "4": {"rcs": (0, 1000, 1, "cycles"), "vcs": (0, 1000, 2, "cycles")},
        "7": {"rcs": (500, 1000, 1, "cycles")},
    }
    after = {
        "4": {"rcs": (300, 2000, 1, "cycles"), "vcs": (1000, 2000, 2, "cycles")},
        "7": {"rcs": (700, 2000, 1, "cycles")},
    }
    result = gpu_busy.shares(before, after, 1.0)
    assert abs(result["rcs"] - 0.5) < 1e-9
    assert abs(result["vcs"] - 0.5) < 1e-9


def test_nanoseconds_are_shared_out_over_the_time_that_passed():
    # i915: nanoseconds busy, against the wall clock between the readings.
    before = {"3": {"render": (1_000_000_000, 0, 1, "ns")}}
    after = {"3": {"render": (1_250_000_000, 0, 1, "ns")}}
    assert abs(gpu_busy.shares(before, after, 0.5)["render"] - 0.5) < 1e-9


def test_a_client_that_came_or_went_between_readings_counts_for_nothing():
    before = {"1": {"rcs": (0, 1000, 1, "cycles")}}
    after = {"2": {"rcs": (900, 2000, 1, "cycles")}}
    assert gpu_busy.shares(before, after, 1.0) == {}


def test_it_says_one_share_a_second():
    try:
        output = subprocess.run([sys.executable, "-I", str(HELPER)], capture_output=True, text=True, timeout=3.5).stdout
    except subprocess.TimeoutExpired as stopped:
        output = stopped.stdout.decode() if isinstance(stopped.stdout, bytes) else (stopped.stdout or "")
    lines = output.splitlines()
    assert len(lines) >= 2, output
    for line in lines:
        assert line == "none" or re.fullmatch(r"(0|1)\.\d{3} \w+", line), line
