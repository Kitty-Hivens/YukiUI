"""What is playing, at the top of quick settings.

A media player of the bench's own stands in for a real one, on the probe's own
session bus, so the person's players are neither seen nor touched.
"""

import json
import subprocess
import sys
import time

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PLAYER = __import__("pathlib").Path(__file__).resolve().parent.parent / "bench/clients/mpris_player.py"
PROBE = SHELL / "benchMediaCardProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.dock

// Written by tests/experimental/test_media_card.py for a test run, and removed after it.
ShellRoot {
    id: probe
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                Config.options.experimental.dock.edge = "bottom";
        }
    }
    Component.onCompleted: {
        if (Config.ready)
            Config.options.experimental.dock.edge = "bottom";
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
            return JSON.stringify({ shown: card.shown && card.visible, title: card.title, playing: card.player?.isPlaying ?? false, progress: card.progress });
        }
        function playPause(): void {
            probe.card()?.player?.togglePlaying();
        }
    }
}
"""


@pytest.fixture
def media(bench):
    bench.forget_notifications()
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("mediaProbe", "ready"), own_bus=True)
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


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
