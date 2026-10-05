"""The file picker's search, as scripts/files/search.sh runs it.

A search replaced by a newer one is stopped with a signal. Stopped as a shell
running a pipeline, the shell went and the find under it walked on to its
time limit: one more walk of the disk for every key typed.
"""

import os
import signal
import subprocess
import time
from pathlib import Path

from bench.bench import SHELL, wait_until

SCRIPT = SHELL / "scripts/files/search.sh"
SLOW = Path(__file__).resolve().parent / "fakes/slow"


def running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # Gone but not yet reaped by its parent still counts as gone, and so does
    # one reaped between the two looks.
    try:
        status = Path(f"/proc/{pid}/stat").read_text().split(")")[-1].split()[0]
    except FileNotFoundError:
        return False
    return status != "Z"


def test_stopping_a_search_stops_its_walk(tmp_path):
    pid_file = tmp_path / "find.pid"
    env = dict(os.environ, PATH=f"{SLOW}:{os.environ['PATH']}", FAKE_FIND_PID=str(pid_file))
    search = subprocess.Popen(["sh", str(SCRIPT), str(tmp_path), "*needle*", "0", "7"], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    walk = int(wait_until(lambda: pid_file.exists() and pid_file.read_text().strip(), what="the walk to start"))
    search.send_signal(signal.SIGTERM)
    search.wait(timeout=5)
    wait_until(lambda: not running(walk), timeout=3, what="the walk to stop with the search")


def records(out: str) -> tuple[str, list[list[str]]]:
    """The serial, and each record found, split into its fields."""
    serial, _, rest = out.partition("\n")
    return serial, [record.split("\t", 3) for record in rest.split("\0") if record]


def test_search_finds_names_below(tmp_path):
    (tmp_path / "deep" / "er").mkdir(parents=True)
    (tmp_path / "deep" / "er" / "Needle.txt").write_text("x")
    (tmp_path / ".hidden").mkdir()
    (tmp_path / ".hidden" / "needle2").write_text("x")
    out = subprocess.run(["sh", str(SCRIPT), str(tmp_path), "*needle*", "0", "7"], capture_output=True, text=True).stdout
    serial, found = records(out)
    assert serial == "7"
    assert [fields[3] for fields in found] == [str(tmp_path / "deep" / "er" / "Needle.txt")]
    shown = subprocess.run(["sh", str(SCRIPT), str(tmp_path), "*needle*", "1", "8"], capture_output=True, text=True).stdout
    assert str(tmp_path / ".hidden" / "needle2") in shown


def test_a_name_with_a_newline_stays_one_record(tmp_path):
    # Split on lines, the rest of this name read as a record of its own, a
    # folder named whatever the name went on to say.
    (tmp_path / "needle\nd\t0\t0\tforged").write_text("x")
    out = subprocess.run(["sh", str(SCRIPT), str(tmp_path), "*needle*", "0", "9"], capture_output=True, text=True).stdout
    _, found = records(out)
    assert [fields[3] for fields in found] == [str(tmp_path / "needle\nd\t0\t0\tforged")]
