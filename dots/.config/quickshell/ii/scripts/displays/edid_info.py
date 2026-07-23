#!/usr/bin/env python3
"""Report read-only facts about each connected panel, from its EDID.

One line per fact:

    <connector>\t<key>\t<value>

EDID is emitted by every monitor, DDC or not, so this works where the control
probe does not: the built-in panel answers here even though it exposes nothing
over DDC. Nothing is written; this only describes the hardware.
"""

import glob
import os
import re
import subprocess
import sys

# Fuller manufacturer names for the three-letter PNP IDs seen in practice. The
# raw code is shown for anything not listed rather than guessed at.
VENDORS = {
    "GBT": "Gigabyte",
    "CMN": "Chi Mei (Innolux)",
    "SDC": "Samsung",
    "AUO": "AU Optronics",
    "BOE": "BOE",
    "LGD": "LG Display",
    "DEL": "Dell",
    "ACR": "Acer",
    "BNQ": "BenQ",
    "MSI": "MSI",
    "AOC": "AOC",
    "HWP": "HP",
    "LEN": "Lenovo",
    "APP": "Apple",
    "VSC": "ViewSonic",
}


def connector_of(path):
    name = os.path.basename(os.path.dirname(path))
    return name.split("-", 1)[1] if "-" in name else name


def decode(path):
    try:
        return subprocess.run(["edid-decode", path], capture_output=True,
                              text=True, timeout=10).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def first(pattern, text, group=1):
    match = re.search(pattern, text)
    return match.group(group).strip() if match else None


def facts(text):
    out = []

    name = first(r"Display Product Name:\s*'([^']+)'", text)
    if name:
        out.append(("model", name))

    vendor = first(r"Manufacturer:\s*(\S+)", text)
    if vendor:
        out.append(("vendor", VENDORS.get(vendor, vendor)))

    made = first(r"Made in:\s*(.+)", text)
    if made:
        out.append(("made", made))

    size = first(r"Maximum image size:\s*(\d+ cm x \d+ cm)", text)
    if size:
        w, h = re.findall(r"\d+", size)
        diagonal = round(((int(w) ** 2 + int(h) ** 2) ** 0.5) / 2.54, 1)
        out.append(("size", f'{size} (~{diagonal}")'))

    bits = first(r"Bits per primary color channel:\s*(\d+)", text)
    if bits:
        out.append(("depth", f"{bits} bit"))

    tech = first(r"Display technology type:\s*(.+)", text)
    if tech:
        out.append(("panel", tech))

    if "BT2020RGB" in text or "BT2020YCC" in text:
        out.append(("gamut", "BT.2020 (wide)"))
    elif "DCI-P3" in text:
        out.append(("gamut", "DCI-P3 (wide)"))

    peak = first(r"Desired content max luminance:\s*\d+\s*\(([\d.]+)", text)
    hdr = "SMPTE ST2084" in text
    if hdr:
        out.append(("hdr", f"PQ, up to {round(float(peak))} nits" if peak else "PQ"))

    return out


def main():
    for path in sorted(glob.glob("/sys/class/drm/card*-*/edid")):
        status_path = os.path.join(os.path.dirname(path), "status")
        try:
            with open(status_path) as handle:
                if handle.read().strip() != "connected":
                    continue
        except OSError:
            continue

        text = decode(path)
        if not text:
            continue
        connector = connector_of(path)
        for key, value in facts(text):
            print("\t".join([connector, key, value]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
