"""The tile editor of quick settings.

Arranging the tiles used to look like quick settings itself with small badges
in the corners, and what was not shown sat in a list behind a button. The
editor now shows every tile plain: those shown, in their order, each with a
button that takes it out, and under them the rest, each with a button that
puts it in. A tile moved either way travels to its new place.
"""

import json
import time

from bench.bench import wait_until
from experimental.test_dock_status_menus import dock  # noqa: F401


def edit(shell):
    shell.call("dock", "quickSettings")
    wait_until(lambda: shell.call("statusMenuProbe", "open") == "other", what="quick settings to open")
    assert shell.call("statusMenuProbe", "pressGlyph", "edit") == "true"
    wait_until(lambda: shell.call("statusMenuProbe", "tileAt", "mic"), what="the editor to lay the tiles out")
    time.sleep(0.4)


def tile(shell, key) -> dict:
    return json.loads(shell.call("statusMenuProbe", "tileAt", key))


def settled(shell, key) -> dict:
    """Where a tile stands once two readings agree."""
    seen = []

    def still():
        seen.append(tile(shell, key))
        return seen[-1] if len(seen) > 1 and seen[-1] == seen[-2] else None
    return wait_until(still, what=f"the tile {key} to come to rest")


def test_a_tile_put_in_goes_up_among_those_shown_and_back(dock):  # noqa: F811
    edit(dock)
    before = settled(dock, "mic")
    assert not before["shown"]
    assert dock.call("statusMenuProbe", "pressTileButton", "mic") == "true"
    assert "mic" in json.loads(dock.call("statusMenuProbe", "pinned"))
    after = settled(dock, "mic")
    assert after["shown"] and after["y"] < before["y"]
    assert dock.call("statusMenuProbe", "pressTileButton", "mic") == "true"
    assert "mic" not in json.loads(dock.call("statusMenuProbe", "pinned"))
    back = settled(dock, "mic")
    assert not back["shown"] and (back["x"], back["y"]) == (before["x"], before["y"])
