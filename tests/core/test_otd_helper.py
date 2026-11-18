"""The helper the pen tablet page talks to OpenTabletDriver through.

It speaks the daemon's JSON-RPC, header-delimited as StreamJsonRpc does, on
the daemon's local socket. These tests stand a fake daemon on a socket of
their own, so the person's driver is never asked or changed. The fake greets
and logs between answers as the real one does, which an answer has to be
picked out from.
"""

import json
import os
import socket
import subprocess
import sys
import threading
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "dots/.config/quickshell/yuki/scripts/tablet/otd.py"

TABLET = {
    "Properties": {
        "Name": "Bench Tablet",
        "Specifications": {
            "Digitizer": {"Width": 160.0, "Height": 100.0, "MaxX": 32000, "MaxY": 20000},
            "Pen": {"MaxPressure": 8191, "ButtonCount": 2},
            "AuxiliaryButtons": {"ButtonCount": 4},
        },
    },
}


def settings():
    return {
        "Revision": "0.6.8.1",
        "Profiles": [{
            "Tablet": "Bench Tablet",
            "OutputMode": {"Path": "OpenTabletDriver.Desktop.Output.LinuxArtistMode", "Settings": [], "Enable": True},
            "Filters": [],
            "AbsoluteModeSettings": {
                "Display": {"Width": 1920.0, "Height": 1080.0, "X": 960.0, "Y": 540.0, "Rotation": 0.0},
                "Tablet": {"Width": 45.0, "Height": 25.0, "X": 70.0, "Y": 50.0, "Rotation": 0.0},
                "EnableClipping": True, "EnableAreaLimiting": False, "LockAspectRatio": False,
            },
            "Bindings": {"TipActivationThreshold": 1.0},
        }],
        "Tools": [],
    }


class FakeDaemon:
    def __init__(self, path: Path):
        self.path = path
        self.settings = settings()
        self.received = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(path))
        self.server.listen()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    @staticmethod
    def send(conn, message):
        body = json.dumps(message).encode()
        conn.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)

    def note(self, conn, text):
        self.send(conn, {"jsonrpc": "2.0", "method": "Message", "params": [{"Group": "IPC", "Message": text, "Level": 0}]})

    def serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                self.note(conn, "Connected to a client.")
                buffer = b""
                while True:
                    while b"\r\n\r\n" not in buffer:
                        chunk = conn.recv(65536)
                        if not chunk:
                            break
                        buffer += chunk
                    if b"\r\n\r\n" not in buffer:
                        break
                    head, buffer = buffer.split(b"\r\n\r\n", 1)
                    length = int(head.split(b":")[1])
                    while len(buffer) < length:
                        buffer += conn.recv(65536)
                    request, buffer = json.loads(buffer[:length]), buffer[length:]
                    self.received.append(request)
                    self.note(conn, "Something logged before the answer.")
                    method = request["method"]
                    if method == "GetTablets":
                        result = [TABLET]
                    elif method == "GetSettings":
                        result = self.settings
                    elif method == "SetSettings":
                        self.settings = request["params"][0]
                        result = None
                    else:
                        self.send(conn, {"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32601, "message": "no such method"}})
                        continue
                    self.send(conn, {"jsonrpc": "2.0", "id": request["id"], "result": result})

    def close(self):
        self.server.close()


@pytest.fixture
def daemon(tmp_path):
    fake = FakeDaemon(tmp_path / "otd.sock")
    yield fake
    fake.close()


def run(tmp_path, *args):
    env = dict(os.environ, YUKI_OTD_SOCKET=str(tmp_path / "otd.sock"), YUKI_OTD_SETTINGS=str(tmp_path / "otd/settings.json"))
    return subprocess.run([sys.executable, "-I", str(HELPER), *args], env=env, capture_output=True, text=True, timeout=10)


def test_state_reads_the_tablet_and_its_settings(tmp_path, daemon):
    result = run(tmp_path, "state")
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    assert state["running"] is True
    assert state["tablets"] == [{"name": "Bench Tablet", "width": 160.0, "height": 100.0,
                                 "maxPressure": 8191, "penButtons": 2, "auxButtons": 4}]
    assert state["settings"]["Profiles"][0]["Tablet"] == "Bench Tablet"


def test_state_without_a_daemon_says_it_is_not_running(tmp_path):
    result = run(tmp_path, "state")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["running"] is False


def test_apply_hands_the_daemon_the_change_and_keeps_it(tmp_path, daemon):
    changes = {
        "tabletArea": {"Width": 160, "Height": 90, "X": 80, "Y": 50, "Rotation": 0},
        "displayArea": {"Width": 2560, "Height": 1440, "X": 1280, "Y": 720, "Rotation": 0},
        "tipThreshold": 12,
        "outputMode": "OpenTabletDriver.Desktop.Output.AbsoluteMode",
    }
    result = run(tmp_path, "apply", "Bench Tablet", json.dumps(changes))
    assert result.returncode == 0, result.stderr

    profile = daemon.settings["Profiles"][0]
    assert profile["AbsoluteModeSettings"]["Tablet"] == {"Width": 160.0, "Height": 90.0, "X": 80.0, "Y": 50.0, "Rotation": 0.0}
    assert profile["AbsoluteModeSettings"]["Display"]["Width"] == 2560.0
    assert profile["Bindings"]["TipActivationThreshold"] == 12.0
    assert profile["OutputMode"]["Path"] == "OpenTabletDriver.Desktop.Output.AbsoluteMode"
    # What was not asked about is handed back as it was.
    assert profile["AbsoluteModeSettings"]["EnableClipping"] is True
    assert daemon.settings["Tools"] == []

    # The daemon does not keep what it is handed, so the file it starts from does.
    written = json.loads((tmp_path / "otd/settings.json").read_text())
    assert written == daemon.settings


def test_apply_to_a_tablet_without_a_profile_changes_nothing(tmp_path, daemon):
    result = run(tmp_path, "apply", "Other Tablet", json.dumps({"tipThreshold": 50}))
    assert result.returncode == 1
    assert "Other Tablet" in result.stderr
    assert not any(request["method"] == "SetSettings" for request in daemon.received)
    assert not (tmp_path / "otd/settings.json").exists()
