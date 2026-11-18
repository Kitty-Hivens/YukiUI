"""What the game guard calls a group of processes when it closes or pauses it.

It was named after the root of its tree, so a development server started from
a terminal was announced as "Closed bash" after thirteen gigabytes of node had
been taken back. It is now named after the process holding most of the memory,
with the root beside it, when that process is another program than the root.
"""

import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("game_guard", REPO / "dots/.config/quickshell/yuki/scripts/system/game-guard.py")
guard_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard_module)

# Above any pid the kernel hands out, so nothing here is a real process.
BASE = 9_000_000
# The file each made-up process runs, by pid.
PATHS = {}


def proc(pid, ppid, name, rss_mb, path=None):
    made = guard_module.Proc(pid=BASE + pid, ppid=BASE + ppid if ppid else 1, sid=BASE + pid, comm=name, cpu=0,
                             rss_kb=rss_mb * 1024, starttime=0, uid=0)
    made.exe = name
    PATHS[made.pid] = path or "/usr/bin/" + name
    return made


def groups_of(*procs):
    guard = guard_module.Guard()
    guard.executable_path = lambda p: PATHS[p.pid]
    return {group.root.pid - BASE: group for group in guard.build_groups({p.pid: p for p in procs}, set())}


def test_a_heavy_child_names_the_group_with_its_root_beside_it():
    groups = groups_of(proc(100, 0, "bash", 5), proc(101, 100, "pnpm", 80), proc(102, 101, "node", 13000))
    assert groups[100].label == "node (from bash)"


def test_a_group_whose_root_holds_the_most_is_named_after_the_root():
    groups = groups_of(proc(200, 0, "firefox", 900), proc(201, 200, "Isolated Web Co", 300))
    assert groups[200].label == "firefox"


def test_a_programs_own_helpers_do_not_rename_it():
    # A browser's tab process, heavier than the browser and titled otherwise,
    # is still the browser.
    groups = groups_of(proc(300, 0, "firefox", 400, "/usr/lib/firefox/firefox"),
                       proc(301, 300, "browser 46 tab", 2000, "/usr/lib/firefox/firefox"))
    assert groups[300].label == "firefox"


def test_a_child_of_the_same_name_does_not_repeat_it():
    groups = groups_of(proc(400, 0, "electron", 100), proc(401, 400, "electron", 700, "/opt/app/electron"))
    assert groups[400].label == "electron"
