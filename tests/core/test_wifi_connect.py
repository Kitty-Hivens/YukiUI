"""Joining a wifi network with a password, as scripts/network/wifi_connect.sh
does it, against a stand-in for nmcli.

Every process on the machine can read every other process's arguments, so the
password must reach nmcli on its stdin and never as an argument.
"""

import json
import os
import subprocess
from pathlib import Path

from bench.bench import SHELL

SCRIPT = SHELL / "scripts/network/wifi_connect.sh"
FAKES = Path(__file__).resolve().parent / "fakes"

PASSWORD = "correct horse: battery staple"


def join(tmp_path, ssid, password, security="WPA2", profiles=None, right=PASSWORD):
    """Runs the script against the stand-in, which takes `right` as the
    password, read off its passwd-file the way nmcli reads it."""
    state = tmp_path / "state.json"
    log = tmp_path / "calls.log"
    state.write_text(json.dumps({"profiles": profiles or {}, "password": right}))
    log.write_text("")
    env = dict(os.environ, PATH=f"{FAKES}:{os.environ['PATH']}", FAKE_NM_STATE=str(state), FAKE_NM_LOG=str(log),
               SSID=ssid, PASSWORD=password, SECURITY=security)
    result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    return result, calls, json.loads(state.read_text())["profiles"]


def arguments(calls):
    return [arg for call in calls for arg in call["argv"]]


def test_new_network_joins_with_the_password_on_stdin_only(tmp_path):
    result, calls, profiles = join(tmp_path, "Home net", PASSWORD)
    assert result.returncode == 0, result.stderr
    assert not any(PASSWORD.strip() in arg for arg in arguments(calls)), "the password was an argument"
    up = next(call for call in calls if call["argv"][:2] == ["connection", "up"])
    assert up["stdin"].startswith("802-11-wireless-security.psk:")
    add = next(call for call in calls if call["argv"][:2] == ["connection", "add"])
    assert add["argv"][add["argv"].index("wifi-sec.key-mgmt") + 1] == "wpa-psk"
    assert list(profiles.values()) == ["Home net"]


def test_password_reaches_nmcli_exactly(tmp_path):
    # nmcli strips spaces from both ends of a secret and reads backslashes as
    # escapes. A password is whatever the person typed.
    odd = " lead\\ing:and\ttrailing "
    result, _, _ = join(tmp_path, "Home net", odd, right=odd)
    assert result.returncode == 0, result.stderr


def test_wrong_password_leaves_no_new_profile(tmp_path):
    result, calls, profiles = join(tmp_path, "Home net", "wrong")
    assert result.returncode != 0
    assert "Secrets were required" in result.stderr
    assert profiles == {}


def test_saved_network_is_brought_up_and_kept(tmp_path):
    saved = {"11111111-2222-3333-4444-555555555555": "Home net"}
    result, calls, profiles = join(tmp_path, "Home net", "wrong", profiles=saved)
    assert result.returncode != 0
    assert not any(call["argv"][:2] == ["connection", "add"] for call in calls)
    assert any(call["argv"][:4] == ["connection", "up", "uuid", "11111111-2222-3333-4444-555555555555"] for call in calls)
    assert profiles == saved


def key_management(tmp_path, security):
    _, calls, _ = join(tmp_path, "Net", PASSWORD, security=security)
    add = next(call for call in calls if call["argv"][:2] == ["connection", "add"])["argv"]
    return add[add.index("wifi-sec.key-mgmt") + 1]


def test_key_management_follows_the_security(tmp_path):
    assert key_management(tmp_path, "WPA3") == "sae"
    assert key_management(tmp_path, "WPA2 WPA3") == "wpa-psk"
    assert key_management(tmp_path, "WPA1 WPA2") == "wpa-psk"
    assert key_management(tmp_path, "WEP") == "none"


def test_enterprise_network_is_refused_without_calling_nmcli(tmp_path):
    result, calls, _ = join(tmp_path, "Office", PASSWORD, security="WPA2 802.1X")
    assert result.returncode != 0 and result.stderr.startswith("Error:")
    assert calls == []
