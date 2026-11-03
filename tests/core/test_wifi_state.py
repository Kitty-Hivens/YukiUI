"""What the Network service says of a network agrees with what the network is.

A network that asked for its password on a failed attempt went on asking for
it after NetworkManager joined it by itself, so the connected network showed a
password field under it.
"""

import json
from pathlib import Path

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

FAKES = Path(__file__).resolve().parent / "fakes/network"
PROBE = SHELL / "benchWifiStateProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_wifi_state.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "wifiProbe"
        function settled(): bool {
            return Network.settled;
        }
        function asking(ssid: string): bool {
            return Network.wifiNetworks.find(n => n.ssid === ssid)?.askingPassword ?? false;
        }
        function active(ssid: string): bool {
            return Network.wifiNetworks.find(n => n.ssid === ssid)?.active ?? false;
        }
        function connect(ssid: string): void {
            Network.connectToWifiNetwork(Network.wifiNetworks.find(n => n.ssid === ssid));
        }
    }
}
"""


def write(path, active):
    path.write_text(json.dumps({
        "networks": [{"ssid": "Home net", "signal": 70, "active": active, "security": "WPA2"}],
        "saved": ["Home net"],
    }))


@pytest.fixture
def network(bench, tmp_path, monkeypatch):
    state = tmp_path / "nm.json"
    write(state, active=False)
    monkeypatch.setenv("PATH", f"{FAKES}:{__import__('os').environ['PATH']}")
    monkeypatch.setenv("FAKE_NM_STATE", str(state))
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("wifiProbe", "settled"))
    try:
        shell.start()
        wait_until(lambda: shell.call("wifiProbe", "settled") == "true", what="the networks to be read")
        yield shell, state
    finally:
        shell.stop()
        shell.remove_probe()


def test_a_network_joined_by_itself_stops_asking_for_its_password(network):
    shell, state = network
    shell.call("wifiProbe", "connect", "Home net")
    wait_until(lambda: shell.call("wifiProbe", "asking", "Home net") == "true", what="the failed attempt to ask for the password")

    # NetworkManager joins it with the secret it holds.
    write(state, active=True)
    wait_until(lambda: shell.call("wifiProbe", "active", "Home net") == "true", what="the network to show as joined")
    wait_until(lambda: shell.call("wifiProbe", "asking", "Home net") == "false", timeout=3,
               what="the joined network to stop asking for a password")
