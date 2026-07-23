#!/usr/bin/env python3
"""Persist the global allow_tearing setting in its own marked block.

Tearing is not a per-output setting, so it lives outside the output region and
outside the docking rules, in a block of its own that this rewrites in place.

Usage: tearing_write.py <config path> <0|1>
"""

import os
import shutil
import sys

BEGIN = "-- >>> yukiui:tearing"
END = "-- <<< yukiui:tearing"


def main():
    if len(sys.argv) != 3:
        print("usage: tearing_write.py <config> <0|1>", file=sys.stderr)
        return 2

    path, on = sys.argv[1], sys.argv[2] == "1"
    block = [
        BEGIN,
        f"hl.config({{ general = {{ allow_tearing = {'true' if on else 'false'} }} }})",
        END,
    ]

    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        shutil.copy2(path, path + ".bak")
    else:
        lines = []

    stripped = [line.strip() for line in lines]
    if BEGIN in stripped and END in stripped:
        start, end = stripped.index(BEGIN), stripped.index(END)
        if end >= start:
            lines[start:end + 1] = block
    else:
        while lines and not lines[-1].strip():
            lines.pop()
        if lines:
            lines.append("")
        lines.extend(block)

    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines).rstrip("\n") + "\n")
    os.replace(temp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
