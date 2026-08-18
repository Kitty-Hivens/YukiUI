#!/usr/bin/env python3
"""Report the DDC/CI controls each connected monitor exposes.

One line per usable feature:

    <connector>\t<bus>\t<vcp>\t<kind>\t<name>\t<values>

kind is "C" for a continuous 0..max control or "NC" for a named-value list;
values is empty for continuous, or a pipe-separated list of "hex=label" pairs.

Read-only: this enumerates what the monitor advertises, it does not write. The
result is what the settings page renders monitor controls from, so a panel that
exposes more shows more, without any of it being hard-coded to one display.
"""

import re
import subprocess
import sys

FEATURE = re.compile(r"^\s*Feature:\s*([0-9A-Fa-f]{2})\s*\((.+?)\)\s*$")
VALUE = re.compile(r"^\s+([0-9A-Fa-f]{2}):\s*(.+?)\s*$")


def detect():
    """Map each DDC-capable connector to its I2C bus number."""
    try:
        out = subprocess.run(["ddcutil", "detect", "--brief"],
                             capture_output=True, text=True, timeout=20).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}

    monitors = {}
    connector = bus = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("DRM connector:"):
            name = line.split(":", 1)[1].strip()
            connector = name.split("-", 1)[1] if "-" in name else name
        elif line.startswith("I2C bus:"):
            match = re.search(r"i2c-(\d+)", line)
            bus = match.group(1) if match else None
        if line == "" and connector and bus:
            monitors[connector] = bus
            connector = bus = None
    if connector and bus:
        monitors[connector] = bus
    return monitors


def features(bus):
    try:
        out = subprocess.run(["ddcutil", "-b", bus, "capabilities"],
                             capture_output=True, text=True, timeout=60).stdout
    except subprocess.TimeoutExpired:
        return []

    parsed = []
    current = None
    for line in out.splitlines():
        feature = FEATURE.match(line)
        if feature:
            current = {"vcp": feature.group(1).upper(), "name": feature.group(2), "values": []}
            parsed.append(current)
            continue
        value = VALUE.match(line)
        if value and current is not None:
            current["values"].append((value.group(1).upper(), value.group(2)))
    return parsed


def main():
    for connector, bus in detect().items():
        for feature in features(bus):
            kind = "NC" if feature["values"] else "C"
            values = "|".join(f"{code}={label}" for code, label in feature["values"])
            print("\t".join([connector, bus, feature["vcp"], kind, feature["name"], values]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
