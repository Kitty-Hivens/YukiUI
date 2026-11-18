"""The game guard keeps other programs on the efficiency cores during a game.

A processor with two performance cores beside eight efficient ones had the
game, the compositor, a chat client and a browser queued for the same two
cores while the eight sat idle. During game mode the guard lets everything
that is not the game or the session run on the efficiency cores only, and
lets it back onto every core afterwards, by what was recorded on disk if the
guard itself is gone.

The process moved here is one the test starts; the record is kept in a folder
of the test's own, not where the running guard keeps its.
"""

import importlib.util
import os
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("game_guard_cores", REPO / "dots/.config/quickshell/yuki/scripts/system/game-guard.py")
guard_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard_module)


def test_kernel_cpu_lists_are_read():
    assert guard_module.cpu_list("4-11") == set(range(4, 12))
    assert guard_module.cpu_list("0,2,4-6\n") == {0, 2, 4, 5, 6}
    assert guard_module.cpu_list("") == set()


@pytest.fixture
def record(tmp_path, monkeypatch):
    monkeypatch.setattr(guard_module, "RUNTIME_DIR", str(tmp_path))
    monkeypatch.setattr(guard_module, "PINNED_PATH", str(tmp_path / "pinned.json"))
    # The process here is seconds old, younger than anything is moved at.
    monkeypatch.setattr(guard_module, "PIN_AFTER", 0.0)
    return tmp_path / "pinned.json"


@pytest.fixture
def sleeper():
    process = subprocess.Popen(["sleep", "60"])
    yield process.pid
    process.kill()
    process.wait()


def group_of(guard, pid, holds_game=False):
    proc = guard.read_one(pid)
    group = guard_module.Group(proc)
    group.pids = [pid]
    group.holds_game = holds_game
    return group, {pid: proc}


def test_a_background_program_goes_to_the_efficiency_cores_and_comes_back(record, sleeper):
    before = os.sched_getaffinity(sleeper)
    if len(before) < 2:
        pytest.skip("one processor, nothing to move between")
    efficient = {max(before)}
    guard = guard_module.Guard()
    guard.efficient = efficient
    group, procs = group_of(guard, sleeper)

    guard.pin_background([group], procs)
    assert os.sched_getaffinity(sleeper) == efficient
    assert str(sleeper) in record.read_text()

    # Gone and started again, the way the unit's --thaw finds it.
    fresh = guard_module.Guard()
    fresh.load_pinned()
    fresh.unpin_all()
    assert os.sched_getaffinity(sleeper) == before


def test_the_game_is_not_moved(record, sleeper):
    before = os.sched_getaffinity(sleeper)
    if len(before) < 2:
        pytest.skip("one processor, nothing to move between")
    guard = guard_module.Guard()
    guard.efficient = {max(before)}
    group, procs = group_of(guard, sleeper, holds_game=True)
    guard.pin_background([group], procs)
    assert os.sched_getaffinity(sleeper) == before
    assert guard.pinned == {}


def test_a_processor_of_one_kind_moves_nothing(record, sleeper):
    before = os.sched_getaffinity(sleeper)
    guard = guard_module.Guard()
    guard.efficient = None
    group, procs = group_of(guard, sleeper)
    guard.pin_background([group], procs)
    assert os.sched_getaffinity(sleeper) == before


def test_a_process_only_just_started_is_left_alone(record, sleeper, monkeypatch):
    # The shell runs a short command every second or so; moving each was a
    # line in the journal per second for nothing.
    monkeypatch.setattr(guard_module, "PIN_AFTER", 3600.0)
    before = os.sched_getaffinity(sleeper)
    if len(before) < 2:
        pytest.skip("one processor, nothing to move between")
    guard = guard_module.Guard()
    guard.efficient = {max(before)}
    group, procs = group_of(guard, sleeper)
    guard.pin_background([group], procs)
    assert os.sched_getaffinity(sleeper) == before
