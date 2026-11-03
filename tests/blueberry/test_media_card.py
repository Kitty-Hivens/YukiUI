"""What is playing, at the top of quick settings.

A media player of the bench's own stands in for a real one, on the probe's own
session bus, so the person's players are neither seen nor touched. The desktop
is plain red, so the panel is easy to find in a capture.
"""

import json
import subprocess
import sys
import time

import pytest

from bench.bench import OUTPUT, SHELL, wait_until
from bench.shell import Shell
from blueberry.test_quick_tiles import panel_corner

PLAYER = __import__("pathlib").Path(__file__).resolve().parent.parent / "bench/clients/mpris_player.py"
PROBE = SHELL / "benchMediaCardProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.dock

// Written by tests/blueberry/test_media_card.py for a test run, and removed after it.
ShellRoot {
    id: probe
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.blueberry.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.blueberry.dock.edge = "bottom";
    }
    ExDock {}

    function find(item, has) {
        if (!item)
            return null;
        if (has(item))
            return item;
        for (const child of item.children ?? []) {
            const found = probe.find(child, has);
            if (found)
                return found;
        }
        return null;
    }
    function card() {
        return probe.find(ExStates.openPopup?.contentItem, item => item.progress !== undefined && item.player !== undefined);
    }

    IpcHandler {
        target: "mediaProbe"
        function ready(): bool {
            return Config.ready;
        }
        function card(): string {
            const card = probe.card();
            if (!card)
                return "";
            const bar = probe.find(card, item => item.heldAt !== undefined);
            return JSON.stringify({ shown: card.shown && card.visible, title: card.title, playing: card.player?.isPlaying ?? false,
                progress: card.progress, timed: card.timed, seekable: card.seekable, bar: !!bar && bar.visible });
        }
        // The bar, from the card's corner, which is where the panel's
        // contents start.
        function bar(): string {
            const card = probe.card();
            const bar = probe.find(card, item => item.heldAt !== undefined);
            const at = bar.mapToItem(card, 0, 0);
            return JSON.stringify({ x: at.x, y: at.y, width: bar.width, height: bar.height, padding: ExStates.openPopup.padding });
        }
        function playPause(): void {
            probe.card()?.player?.togglePlaying();
        }
    }
}
"""


@pytest.fixture
def media(bench):
    bench.eval('hl.config({ misc = { force_default_wallpaper = 0, background_color = "rgb(ff0000)" } })')
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("mediaProbe", "ready"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        bench.eval('hl.config({ misc = { force_default_wallpaper = -1, background_color = "rgb(111111)" } })')


def start_player(shell, *flags):
    player = subprocess.Popen([sys.executable, str(PLAYER), "bench", "Bench Song", "Bench Band", *flags],
                              env=shell.environment(), stdout=subprocess.PIPE, text=True)
    assert player.stdout.readline().strip() == "ready"
    return player


def stop_player(player):
    player.kill()
    player.wait(timeout=5)


def card(shell) -> dict:
    text = shell.call("mediaProbe", "card")
    return json.loads(text) if text else {}


def test_no_player_no_card(media):
    media.call("dock", "quickSettings")
    time.sleep(1.0)
    assert not card(media).get("shown", False)


def test_a_playing_track_is_shown_and_answers(media):
    player = subprocess.Popen([sys.executable, str(PLAYER), "bench", "Bench Song", "Bench Band"],
                              env=media.environment(), stdout=subprocess.PIPE, text=True)
    try:
        assert player.stdout.readline().strip() == "ready"
        media.call("dock", "quickSettings")
        state = wait_until(lambda: (lambda c: c if c.get("shown") else None)(card(media)), what="the card to show")
        assert state["title"] == "Bench Song"
        # A minute into five.
        wait_until(lambda: abs(card(media)["progress"] - 0.2) < 0.01, what="how far the track has got")
        media.call("mediaProbe", "playPause")
        # A playing player is told to pause, not to toggle.
        assert player.stdout.readline().strip() == "Pause"
        wait_until(lambda: card(media)["playing"] is False, what="the card to say it is paused")
        assert not media.errors()
    finally:
        player.kill()
        player.wait(timeout=5)


def test_a_player_that_does_not_say_how_long_keeps_an_empty_bar(media):
    player = start_player(media, "--untimed")
    try:
        media.call("dock", "quickSettings")
        state = wait_until(lambda: (lambda c: c if c.get("shown") else None)(card(media)), what="the card to show")
        # The bar stands empty, so the card keeps its height once the player
        # starts to say.
        assert state["bar"] and not state["timed"] and state["progress"] == 0
        assert not media.errors()
    finally:
        stop_player(player)


def test_the_bar_moves_the_track(bench, desk, media, tmp_path):
    player = start_player(media, "--seekable")
    try:
        media.call("dock", "quickSettings")
        wait_until(lambda: card(media).get("seekable"), what="the card to say the track can be moved through")
        time.sleep(1.0)
        shot = tmp_path / "card.png"
        subprocess.run(["grim", "-o", OUTPUT, str(shot)], env=bench.environment(), check=True)
        left, top = panel_corner(shot)
        bar = json.loads(media.call("mediaProbe", "bar"))
        x = round(left + bar["padding"] + bar["x"] + bar["width"] / 2)
        y = round(top + bar["padding"] + bar["y"] + bar["height"] / 2)
        pointer = desk.pointer()
        pointer.move(x - 40, y)
        pointer.glide(x, y)
        pointer.click(x, y)
        # Half way through five minutes, give or take the pixel a click drifts.
        command, seconds = wait_until(lambda: player.stdout.readline().strip(), what="the player to be moved").split()
        assert command == "SetPosition" and abs(int(seconds) - 150) <= 2, (command, seconds)
        wait_until(lambda: abs(card(media)["progress"] - 0.5) < 0.01, what="the card to follow")
        assert not media.errors()
    finally:
        stop_player(player)
