"""The compositor rules of the environment that is up, as the shell writes them.

The compositor reloads its whole config whenever a file it read is replaced,
which re-registers every global shortcut and drops every setting made at
runtime. The shell writes the rules each time it starts, so writing them must
cost a reload only when they change, and the first time, when the config did
not read the file because it was not there yet.
"""

import subprocess
import time

import pytest

from bench.bench import SHELL

SCRIPT = SHELL / "scripts/hyprland/environment_rules.sh"


@pytest.fixture
def rules(bench, tmp_path):
    bench.environment_rules.unlink(missing_ok=True)
    bench.reload()

    def write(probe: str):
        source = tmp_path / "rules.lua"
        source.write_text(f'YUKI_RULES_PROBE = "{probe}"\n')
        subprocess.run(["bash", str(SCRIPT), "-- header", str(source), str(bench.environment_rules)],
                       env=bench.environment(), check=True)

    yield write
    bench.environment_rules.unlink(missing_ok=True)
    bench.reload()


def reloads_after(bench, mark, settle: float = 1.5) -> int:
    time.sleep(settle)
    return len(bench.events.since(mark, "configreloaded"))


def test_first_write_is_read_at_once(bench, rules):
    mark = bench.events.mark()
    rules("first")
    assert reloads_after(bench, mark) == 1
    assert bench.lua_value("YUKI_RULES_PROBE") == "first"


def test_same_rules_again_do_not_reload(bench, rules):
    rules("same")
    mark = bench.events.mark()
    rules("same")
    assert reloads_after(bench, mark) == 0
    assert not list(bench.environment_rules.parent.glob("environment.lua.*")), "a staged copy was left behind"


def test_changed_rules_are_read(bench, rules):
    rules("before")
    mark = bench.events.mark()
    rules("after")
    assert reloads_after(bench, mark) == 1
    assert bench.lua_value("YUKI_RULES_PROBE") == "after"
