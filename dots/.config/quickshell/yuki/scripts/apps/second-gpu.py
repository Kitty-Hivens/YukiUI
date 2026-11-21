#!/usr/bin/env python3
"""
Which applications ask to run on the second graphics card, and how a program
is run there.

    second-gpu.py

Prints one line of JSON: {"entries": [ids], "environment": {name: value},
"source": "switcheroo" | "nvidia" | ""}. The environment is empty on a machine
with one graphics card, or when it cannot be told how to reach the second.

A desktop entry asks with PrefersNonDefaultGPU=true, the freedesktop key, or
X-KDE-RunOnDiscreteGpu=true, the older key KDE read before it. Steam asks, and
GNOME and KDE start it on the discrete card, so its games run there too. An
entry kept in the person's own folder overrides the one of the same id further
down the search path, as it does for every launcher, and a key it leaves out is
left out.

The environment comes from switcheroo-control, the system service GNOME and KDE
ask, which knows every card and how to address each. Without it, a laptop with
an NVIDIA card beside the one that drives the screen is addressed the way the
NVIDIA driver documents for render offload.
"""

import json
import os
import subprocess
import sys

KEYS = ("PrefersNonDefaultGPU", "X-KDE-RunOnDiscreteGpu")

# What the NVIDIA driver reads to render on its card in a session drawn on
# another: OpenGL through glvnd, and Vulkan with the other card's devices hidden.
NVIDIA_OFFLOAD = {
    "__NV_PRIME_RENDER_OFFLOAD": "1",
    "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
    "__VK_LAYER_NV_optimus": "NVIDIA_only",
}


def application_dirs():
    """The applications folders, the one that wins first."""
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    seen = []
    for base in [home] + dirs.split(":"):
        path = os.path.join(base, "applications")
        if base and path not in seen:
            seen.append(path)
    return seen


def asks_for_second_gpu(path):
    """Whether the [Desktop Entry] group of a file sets one of the keys to true."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            group = None
            for line in handle:
                line = line.strip()
                if line.startswith("["):
                    group = line
                    continue
                if group != "[Desktop Entry]" or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                if key.strip() in KEYS and value.strip().lower() == "true":
                    return True
    except OSError:
        pass
    return False


def preferring_entries(dirs):
    """Ids of the entries that ask, each decided by the folder that wins for it."""
    decided = set()
    asking = []
    for root in dirs:
        if not os.path.isdir(root):
            continue
        for folder, _, files in os.walk(root):
            for name in files:
                if not name.endswith(".desktop"):
                    continue
                path = os.path.join(folder, name)
                # An entry in a subfolder is named by its path, the slashes made dashes.
                entry_id = os.path.relpath(path, root)[: -len(".desktop")].replace(os.sep, "-")
                if entry_id in decided:
                    continue
                decided.add(entry_id)
                if asks_for_second_gpu(path):
                    asking.append(entry_id)
    return sorted(asking)


def plain(value):
    """A value as busctl writes it in JSON, with its type beside it or not."""
    if isinstance(value, dict) and "data" in value:
        return value["data"]
    return value


def switcheroo_environment(text):
    """The environment of the first card that is not the default, from busctl's JSON."""
    try:
        gpus = plain(json.loads(text))
    except ValueError:
        return {}
    for gpu in gpus or []:
        if not isinstance(gpu, dict) or plain(gpu.get("Default")):
            continue
        pairs = plain(gpu.get("Environment")) or []
        environment = {}
        for index in range(0, len(pairs) - 1, 2):
            environment[str(pairs[index])] = str(pairs[index + 1])
        if environment:
            return environment
    return {}


def ask_switcheroo():
    try:
        result = subprocess.run(
            ["busctl", "--system", "--json=short", "get-property", "net.hadess.SwitcherooControl",
             "/net/hadess/SwitcherooControl", "net.hadess.SwitcherooControl", "GPUs"],
            capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if result.returncode != 0:
        return {}
    return switcheroo_environment(result.stdout)


def nvidia_beside_another(drm="/sys/class/drm", driver="/proc/driver/nvidia/version"):
    """Whether an NVIDIA card with its driver loaded sits beside another that drives the screen."""
    if not os.path.exists(driver):
        return False
    nvidia = other = False
    try:
        names = os.listdir(drm)
    except OSError:
        return False
    for name in names:
        # The cards themselves, not their connectors (card1-eDP-1).
        if not name.startswith("card") or "-" in name:
            continue
        device = os.path.join(drm, name, "device")
        try:
            with open(os.path.join(device, "vendor")) as handle:
                vendor = handle.read().strip()
        except OSError:
            continue
        if vendor == "0x10de":
            nvidia = True
        else:
            other = True
    return nvidia and other


def main():
    environment = ask_switcheroo()
    source = "switcheroo" if environment else ""
    if not environment and nvidia_beside_another():
        environment = dict(NVIDIA_OFFLOAD)
        source = "nvidia"
    # Nothing to run them on: which entries ask is not worth the walk.
    entries = preferring_entries(application_dirs()) if environment else []
    json.dump({"entries": entries, "environment": environment, "source": source}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
