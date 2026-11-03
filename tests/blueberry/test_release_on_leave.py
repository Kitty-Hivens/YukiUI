"""What Blueberry lets go of as another takes its place.

Its tags hold a window at its size and square its corners only while its
rules name them, but they are its own marks, and it takes them off as it goes.
The Lua it runs is taken from ExPlacement.releaseAll and run here as it runs
it: the bench brings up no environments, so there is no switch to make.
"""

import re
import time

from bench.bench import SHELL
from blueberry.test_maximize import is_maximized

SOURCE = (SHELL / "blueberry/windows/ExPlacement.qml").read_text()
LUA = re.search(r"function releaseAll\(\).*?\"eval\", `(.*?)`", SOURCE, re.S).group(1)


def test_placed_windows_lose_the_tags(bench, desk):
    maximized = desk.wayland()
    snapped = desk.wayland()
    desk.place(maximized, "maximized")
    desk.place(snapped, "left")
    maximized.wait(lambda c: is_maximized(desk, c), "maximised")
    snapped.wait(lambda c: "snapped" in c["tags"], "snapped")
    rect = (*maximized.client()["at"], *maximized.client()["size"])
    bench.eval(LUA)
    maximized.wait(lambda c: not c["tags"], "no tags left")
    snapped.wait(lambda c: not c["tags"], "no tags left")
    time.sleep(0.3)
    assert (*maximized.client()["at"], *maximized.client()["size"]) == rect, "the window was moved"
    assert bench.lua_value("next(YUKI_PLACED) == nil") == "true"
