#!/usr/bin/env python3
"""How busy the graphics card is, as the kernel accounts it to each program.

Intel's drivers keep no figure for the card as a whole, only its clock, and the
clock says little: the card runs at its fastest under almost any load. What the
kernel does keep is how long each program had each engine, in the fdinfo of
every open DRM file, which is what intel_gpu_top and nvtop read. Added up over
every program, an engine's share of a second is how busy it was.

    gpu_busy.py [SECONDS]

Prints one line every SECONDS, one by default, the busiest engine's share of
that whole span from 0 to 1 with the engine's name, or "none" while no
program's accounts can be read:

    0.213 rcs

Runs until its output is closed. Only the open DRM files found are read each
time; the processes are searched for new ones every few seconds at most, since
a walk of all of /proc each second is work the reading would then show.

xe counts in cycles of the card's own clock, beside the cycles that passed:
drm-cycles-<engine> against drm-total-cycles-<engine>. i915 counts nanoseconds
busy, drm-engine-<engine>, against the time that passed. Either may say an
engine class has more than one engine, drm-engine-capacity-<engine>, and the
share is then of all of them.
"""

import os
import sys
import time

RESCAN_SECONDS = 5


def drm_files():
    """(pid, fd) of every open DRM file this user may read the accounts of."""
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        folder = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(folder)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{folder}/{fd}")
            except OSError:
                continue
            if target.startswith("/dev/dri/"):
                found.append((pid, fd))
    return found


def read_accounts(files):
    """client id -> {engine: (busy, total, capacity, kind)}, one entry a client.

    A client is one opening of the device, and a file passed on to another
    process, as a compositor is handed a client's buffers, is the same client
    seen twice: counted once.
    """
    clients = {}
    for pid, fd in files:
        try:
            with open(f"/proc/{pid}/fdinfo/{fd}") as handle:
                text = handle.read()
        except OSError:
            continue
        fields = {}
        for line in text.splitlines():
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip()
        client = fields.get("drm-client-id")
        if client is None or client in clients:
            continue
        engines = {}
        for key, value in fields.items():
            if key.startswith("drm-cycles-"):
                name = key[len("drm-cycles-"):]
                total = fields.get(f"drm-total-cycles-{name}")
                if total is not None:
                    engines[name] = (int(value.split()[0]), int(total.split()[0]), "cycles")
            elif key.startswith("drm-engine-") and not key.startswith("drm-engine-capacity-"):
                name = key[len("drm-engine-"):]
                engines[name] = (int(value.split()[0]), 0, "ns")
        capacities = {key[len("drm-engine-capacity-"):]: int(value.split()[0])
                      for key, value in fields.items() if key.startswith("drm-engine-capacity-")}
        clients[client] = {name: (busy, total, capacities.get(name, 1), kind) for name, (busy, total, kind) in engines.items()}
    return clients


def shares(before, after, seconds):
    """engine -> its share of the time between two readings, over every client."""
    result = {}
    for client, engines in after.items():
        earlier = before.get(client)
        if earlier is None:
            continue
        for name, (busy, total, capacity, kind) in engines.items():
            if name not in earlier:
                continue
            busy_then, total_then, _, _ = earlier[name]
            spent = busy - busy_then
            if kind == "cycles":
                passed = total - total_then
            else:
                passed = seconds * 1e9
            if spent < 0 or passed <= 0:
                continue
            result[name] = result.get(name, 0.0) + spent / (passed * max(1, capacity))
    return result


def main():
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    interval = min(60.0, max(0.2, interval))
    files = drm_files()
    scanned = time.monotonic()
    before = read_accounts(files)
    then = scanned
    while True:
        time.sleep(interval)
        if time.monotonic() - scanned >= RESCAN_SECONDS:
            files = drm_files()
            scanned = time.monotonic()
        after = read_accounts(files)
        now = time.monotonic()
        busiest = max(shares(before, after, now - then).items(), key=lambda item: item[1], default=None)
        before, then = after, now
        try:
            if busiest is None:
                print("none", flush=True)
            else:
                print(f"{min(1.0, busiest[1]):.3f} {busiest[0]}", flush=True)
        except BrokenPipeError:
            return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
