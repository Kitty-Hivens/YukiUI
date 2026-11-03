"""Under ii a window that opens goes into the tiling.

An application that remembers having been closed maximised, kitty among them,
asks to be maximised again a moment after it opens. Hyprland's maximise is a
fullscreen of its own over the layout, so the window covered the tiling and
looked like a floating one. That first request is dropped. One asked for later
still maximises.
"""

import time

import pytest

from bench.bench import SHELL, Bench
from bench.windows import WaylandWindow


@pytest.fixture(scope="module")
def ii_bench(tmp_path_factory):
    bench = Bench(tmp_path_factory.mktemp("iibench"), rules=SHELL / "environments/ii/compositor/rules.lua")
    bench.start()
    yield bench
    bench.stop()


@pytest.fixture
def window(ii_bench):
    opened = []

    def open_window(name):
        window = WaylandWindow(ii_bench, f"bench.ii.{name}")
        opened.append(window)
        return window

    yield open_window
    for window in opened:
        try:
            window.close()
        except Exception:
            window.kill()


def test_a_maximise_asked_for_as_the_window_opens_is_dropped(window):
    first = window("first")
    second = window("second")
    second.command("maximize")
    time.sleep(0.6)
    client = second.client()
    assert client["fullscreen"] == 0, f"the window opened over the tiling: {client['fullscreen']}"
    assert not client["floating"]
    # Tiled beside the first, which a maximised window would cover.
    assert first.client()["size"][0] < 1920 // 2 + 50


def test_a_maximise_asked_for_later_still_maximises(window):
    first = window("later")
    time.sleep(2.0)
    first.command("maximize")
    first.wait(lambda c: c["fullscreen"] == 1, "maximised")
