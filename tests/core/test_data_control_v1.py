"""The data-control-v1 plugin: a first-version wlr-data-control client keeps
its clipboard.

Hyprland 0.56 sends the second version's primary selection event to every
client of the protocol, and one of the first version, Wine's Wayland driver
among them, has no handler for it: libwayland aborts its thread. The bench's
client is such a client, and must live through clipboard changes with the
plugin, and die without it, which shows it is a fair stand-in.
"""

import subprocess
import time

from bench.bench import wait_until


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
    assert "data-control-v1" in bench.hyprctl("plugin", "list")
    client = start_client(bench)
    try:
        copy_both(bench)
        assert client.poll() is None, "the first-version client died"
    finally:
        client.kill()
        client.wait()


def test_without_the_plugin_it_dies(bench):
    path = str(bench.build / "data-control-v1.so")
    bench.hyprctl("plugin", "unload", path)
    try:
        wait_until(lambda: "data-control-v1" not in bench.hyprctl("plugin", "list"), what="the plugin to go")
        copy_both(bench)
        client = subprocess.Popen([str(bench.data_control_client)], env=bench.environment(), stdout=subprocess.PIPE, text=True)
        wait_until(lambda: client.poll() is not None, what="the client to die on the event it has no handler for")
        assert client.returncode != 0
    finally:
        bench.hyprctl("plugin", "load", path)
        wait_until(lambda: "data-control-v1" in bench.hyprctl("plugin", "list"), what="the plugin to come back")
