"""A first-version wlr-data-control client keeps its clipboard.

Hyprland 0.56 sent the second version's primary selection event to every
client of the protocol, and one of the first version, Wine's Wayland driver
among them, has no handler for it: libwayland aborts its thread. A plugin held
the event back until Hyprland checked the version itself. The bench's client
is such a client, and must live through clipboard changes with Hyprland alone.
"""

import subprocess
import time


def start_client(bench):
    client = subprocess.Popen([str(bench.data_control_client)], env=bench.environment(), stdout=subprocess.PIPE, text=True)
    # The clipboard as it stands is handed over as the device is set up, so
    # a selection can come before it says it is ready.
    for line in client.stdout:
        if line.strip() == "ready":
            return client
    raise AssertionError(f"the client ended before it was ready, with {client.wait()}")


def copy_both(bench):
    env = bench.environment()
    subprocess.run(["wl-copy", "plain"], env=env, check=True)
    subprocess.run(["wl-copy", "--primary", "primary"], env=env, check=True)
    time.sleep(0.5)


def test_a_first_version_client_lives_through_clipboard_changes(bench):
    client = start_client(bench)
    try:
        copy_both(bench)
        assert client.poll() is None, "the first-version client died"
    finally:
        client.kill()
        client.wait()
