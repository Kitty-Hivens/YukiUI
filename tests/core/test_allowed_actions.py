"""What an X11 application is told it may do with its window.

An application that draws its own title bar reads _NET_WM_ALLOWED_ACTIONS to
know which of its buttons will be honoured, and first looks in the root
window's _NET_SUPPORTED for whether that list is kept at all. Hyprland keeps
none of it. The environment says what it honours, in its compositor rules,
and the minimize plugin tells each X11 window, as the window stands now. An
application that finds the list declared but none on its window takes
everything for allowed, so the two go together or not at all.

Each environment is read here from its own rules, on a compositor of its own.
The facts the lists rest on were measured on the bench as well: a floating X11
window is moved and resized by its own ConfigureRequest and a tiled one is
not, ii maximises on _NET_WM_STATE and does nothing with WM_CHANGE_STATE.
"""

import json
import shutil
import subprocess
import sys
import time

import pytest

from bench.bench import SHELL, Bench, wait_until
from bench.windows import X11Window

ACTION = "_NET_WM_ACTION_"
EVERYTHING = ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT", "MINIMIZE", "MOVE", "RESIZE"]
MAXIMIZED = {"_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ"}


# What an application that draws its own title bar does first, before it has a
# window: wait for the declaration on the root, then look the action atoms up
# without making them, as Nexira does. Prints which of them exist.
EARLY_LOOKUP = r"""
import contextlib, json, sys, time
from Xlib import X, display
names = ["_NET_WM_ACTION_" + n for n in ("MOVE", "RESIZE", "MINIMIZE", "MAXIMIZE_HORZ", "MAXIMIZE_VERT", "FULLSCREEN", "CLOSE")]
# python-xlib writes its warning about a missing Xauthority to stdout.
with contextlib.redirect_stdout(sys.stderr):
    d = display.Display()
root = d.screen().root
deadline = time.time() + 10
while time.time() < deadline:
    supported = d.intern_atom("_NET_SUPPORTED", only_if_exists=True)
    prop = root.get_full_property(supported, X.AnyPropertyType) if supported else None
    if prop and "_NET_WM_ALLOWED_ACTIONS" in [d.get_atom_name(a) for a in prop.value]:
        print(json.dumps({n: d.intern_atom(n, only_if_exists=True) != 0 for n in names}))
        sys.exit(0)
    time.sleep(0.05)
print("null")
"""


def actions(window):
    listed = window.command("allowed")["allowed"]
    return None if listed is None else sorted(name.removeprefix(ACTION) for name in listed)


def becomes(window, expected, what):
    return wait_until(lambda: actions(window) == expected, timeout=4, what=f"{what}: {expected}, last {actions(window)}")


def declared(window):
    return "_NET_WM_ALLOWED_ACTIONS" in window.command("supported")["supported"]


def dispatch(bench, window, name, args):
    bench.eval(f'hl.dispatch(hl.dsp.window.{name}({{ {args}, window = "address:{window.address}" }}))')


def family_bench(tmp_path_factory, name, rules_of=None):
    root = tmp_path_factory.mktemp(name)
    # A copy, so a test can change what the rules say and read them again.
    rules = root / "rules.lua"
    shutil.copy(SHELL / f"environments/{rules_of or name}/compositor/rules.lua", rules)
    bench = Bench(root / "bench", rules=rules)
    bench.start()
    return bench


@pytest.fixture(scope="module")
def blueberry(tmp_path_factory):
    bench = family_bench(tmp_path_factory, "blueberry")
    yield bench
    bench.stop()


@pytest.fixture(scope="module")
def ii(tmp_path_factory):
    bench = family_bench(tmp_path_factory, "ii")
    yield bench
    bench.stop()


@pytest.fixture
def x11():
    opened = []

    def open_window(bench, name, **kwargs):
        window = X11Window(bench, f"bench.actions.{name}", **kwargs)
        opened.append(window)
        return window

    yield open_window
    for window in opened:
        try:
            window.close()
        except Exception:
            window.kill()


def test_the_actions_exist_before_any_window_is_told(tmp_path_factory):
    # Declared on the root but made only as the first window was told, the
    # action atoms did not exist when an application looked them up without
    # making them. It took every one of them for unknown and read each list as
    # allowing nothing. Its own fresh compositor, so no window was ever told.
    bench = family_bench(tmp_path_factory, "blueberry-fresh", rules_of="blueberry")
    try:
        lookup = subprocess.run([sys.executable, "-c", EARLY_LOOKUP], env=bench.environment(),
                                capture_output=True, text=True, timeout=30)
        assert lookup.stdout.strip(), f"the lookup said nothing: {lookup.stderr}"
        exist = json.loads(lookup.stdout)
        assert exist is not None, "the root never declared the allowed actions"
        assert all(exist.values()), f"declared before these existed: {[n for n, made in exist.items() if not made]}"
    finally:
        bench.stop()


def test_a_floating_window_in_blueberry_may_do_everything(blueberry, x11):
    window = x11(blueberry, "floating")
    assert declared(window)
    becomes(window, EVERYTHING, "everything for a floating window")


def test_a_window_held_at_its_size_is_neither_moved_nor_resized(blueberry, x11):
    # Blueberry maximises by giving a window the work area and the tag that
    # holds its size, and a window pulled away is put back by the shell.
    window = x11(blueberry, "held")
    becomes(window, EVERYTHING, "everything before it is held")
    dispatch(blueberry, window, "tag", 'tag = "+maximized"')
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT", "MINIMIZE"], "no moving or resizing once held")
    dispatch(blueberry, window, "tag", 'tag = "-maximized"')
    becomes(window, EVERYTHING, "everything again once let go")


def test_a_tiled_window_in_ii_is_placed_by_the_layout(ii, x11):
    x11(ii, "first")
    window = x11(ii, "tiled")
    window.wait(lambda c: not c["floating"], "tiled")
    assert declared(window)
    # Nothing minimises here, and the layout places a tiled window.
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT"], "a tiled window")
    dispatch(ii, window, "float", 'action = "toggle"')
    window.wait(lambda c: c["floating"], "floating")
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT", "MOVE", "RESIZE"], "a floating window")


def test_a_window_ii_maximises_is_told_so(ii, x11):
    window = x11(ii, "maximised")
    # ii drops a maximise asked for as a window opens.
    time.sleep(1.8)
    window.command("netstate add maximized")
    window.wait(lambda c: c["fullscreen"] == 1, "maximised")
    window.wait_state(lambda s: MAXIMIZED <= set(s["net_wm_state"]), "told it is maximised")
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT"], "a maximised window")
    window.command("netstate remove maximized")
    window.wait(lambda c: c["fullscreen"] == 0, "put back")
    window.wait_state(lambda s: not MAXIMIZED & set(s["net_wm_state"]), "told it is not maximised")


def test_nothing_is_promised_once_nothing_is_said(ii, x11):
    window = x11(ii, "unsaid")
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT"], "the list as ii says it")
    ii.eval("hl.plugin.minimize.allowed_actions(nil)")
    assert not declared(window)
    becomes(window, None, "no list once nothing is said")

    # Read again, the rules say it again.
    ii.reload()
    assert declared(window)
    becomes(window, ["CLOSE", "FULLSCREEN", "MAXIMIZE_HORZ", "MAXIMIZE_VERT"], "the list said again")

    # Rules that no longer say it, as another environment's, take it back.
    said = ii.rules.read_text()
    try:
        ii.rules.write_text(said.replace("hl.plugin.minimize.allowed_actions(", "local _ = (", 1))
        ii.reload()
        assert not declared(window)
        becomes(window, None, "no list after rules that do not say it")
    finally:
        ii.rules.write_text(said)
        ii.reload()
