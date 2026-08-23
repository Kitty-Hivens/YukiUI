#!/usr/bin/env python3
"""Merge generated colour groups into kdeglobals without disturbing the rest.

kdeglobals is not an output file. Every KDE application writes to it -- dialog
geometry, sort order, the last used accent -- so a generated palette has to be
folded in group by group rather than dropped over the top.

Reads the fragment named first, applies it to the file named second, writes the
result in place. Groups the fragment does not mention are left exactly as they
were; keys it does mention win.
"""

import configparser
import sys
from pathlib import Path


def reader() -> configparser.RawConfigParser:
    # KDE keys are case sensitive and carry spaces ("Show hidden files"), and a
    # group name can hold a second bracketed part ("[Colors:Header][Inactive]").
    # RawConfigParser with optionxform off leaves all three alone; interpolation
    # would otherwise choke on a stray "%" in a value.
    parser = configparser.RawConfigParser(delimiters=("=",), comment_prefixes=("#", ";"))
    parser.optionxform = str
    return parser


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} <fragment> <kdeglobals>", file=sys.stderr)
        return 2

    fragment_path, target_path = Path(sys.argv[1]), Path(sys.argv[2])
    if not fragment_path.is_file():
        print(f"no fragment at {fragment_path}", file=sys.stderr)
        return 1

    fragment = reader()
    fragment.read(fragment_path, encoding="utf-8")

    target = reader()
    if target_path.is_file():
        target.read(target_path, encoding="utf-8")

    for group in fragment.sections():
        if not target.has_section(group):
            target.add_section(group)
        for key, value in fragment.items(group):
            target.set(group, key, value)

    # Written beside the original and moved over it, so an interrupted run cannot
    # leave a half-written kdeglobals behind -- every KDE application reads it.
    temporary = target_path.with_suffix(target_path.suffix + ".tmp")
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with temporary.open("w", encoding="utf-8") as handle:
        target.write(handle, space_around_delimiters=False)
    temporary.replace(target_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
