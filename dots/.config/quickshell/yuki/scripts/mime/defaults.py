#!/usr/bin/env python3
"""Which application opens what, grouped the way a person asks the question.

The system stores this per MIME type, and a person thinks in categories: "what
opens my pictures", not "what opens image/jpeg as opposed to image/png". The two
drift apart silently -- one viewer ends up on PNG and another on JPEG -- and
nothing anywhere says so. So this reports per category AND says when the types
inside one disagree.

`report` prints JSON. `set` changes every type of one category at once, which is
what a person means by "open pictures with this".
"""

import argparse
import configparser
import json
import os
import subprocess
import sys
from pathlib import Path

# Ordered as the page shows them. The types are the ones a desktop actually hands
# out; a category is a claim that a person wants one application for all of them.
GROUPS: list[dict] = [
    {"key": "browser", "name": "Web browser", "icon": "public",
     "types": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"]},
    {"key": "mail", "name": "Email", "icon": "mail",
     "types": ["x-scheme-handler/mailto"]},
    {"key": "files", "name": "File manager", "icon": "folder",
     "types": ["inode/directory"]},
    {"key": "images", "name": "Images", "icon": "image",
     "types": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/svg+xml"]},
    {"key": "video", "name": "Video", "icon": "movie",
     "types": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime"]},
    {"key": "audio", "name": "Audio", "icon": "music_note",
     "types": ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4"]},
    {"key": "documents", "name": "Documents", "icon": "description",
     "types": ["application/pdf", "application/epub+zip"]},
    {"key": "text", "name": "Plain text and code", "icon": "code",
     "types": ["text/plain", "text/markdown", "application/json", "application/x-shellscript"]},
    {"key": "archives", "name": "Archives", "icon": "folder_zip",
     "types": ["application/zip", "application/x-tar", "application/x-compressed-tar",
               "application/x-7z-compressed", "application/vnd.rar"]},
]


def data_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    raw = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    seen, out = set(), []
    for part in [str(home)] + raw.split(":"):
        part = part.strip()
        if part and part not in seen:
            seen.add(part)
            out.append(Path(part) / "applications")
    return out


def read_entries() -> dict[str, dict]:
    """Every installed .desktop, by id, lowest precedence first so nearer wins.

    Hidden and NoDisplay entries are kept: an association can legitimately point
    at one (a handler with no launcher of its own), and dropping it would show an
    empty default where there is a working one.
    """
    found: dict[str, dict] = {}
    for directory in reversed(data_dirs()):
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.desktop")):
            entry_id = str(path.relative_to(directory)).replace("/", "-")
            parser = configparser.RawConfigParser(delimiters=("=",), comment_prefixes=("#",), strict=False)
            parser.optionxform = str
            try:
                parser.read(path, encoding="utf-8")
            except (configparser.Error, UnicodeDecodeError):
                continue
            if not parser.has_section("Desktop Entry"):
                continue
            section = parser["Desktop Entry"]
            if section.get("Type", "Application") != "Application":
                continue
            found[entry_id] = {
                "id": entry_id,
                "name": section.get("Name", entry_id),
                "icon": section.get("Icon", ""),
                "types": [t.strip() for t in section.get("MimeType", "").split(";") if t.strip()],
                "noDisplay": section.get("NoDisplay", "false").strip().lower() == "true",
            }
    return found


def default_for(mime: str) -> str:
    try:
        out = subprocess.run(["xdg-mime", "query", "default", mime],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def report() -> dict:
    entries = read_entries()
    groups = []
    for group in GROUPS:
        per_type = {mime: default_for(mime) for mime in group["types"]}
        # Every application declaring at least one type of the group, carrying how
        # much of the group it actually covers.
        #
        # Coverage is the number that matters and it used to be invisible: picking
        # an application that handles two of five audio formats leaves the other
        # three where they were, so a category asked to agree came out MORE split
        # than before. Seen happening: Firefox chosen for audio, which declares
        # flac and ogg and nothing else, turning two handlers into three.
        candidates = []
        for eid, entry in entries.items():
            covers = [t for t in group["types"] if t in entry["types"]]
            if not covers:
                continue
            candidates.append(dict(entry, covers=len(covers), total=len(group["types"])))
        # Whole-category handlers first: those are the ones that answer the
        # question the page asks. Ties by name, so the order does not wander.
        candidates.sort(key=lambda c: (-c["covers"], c["name"].lower()))
        # Two applications can carry the same Name -- Loupe and one other are both
        # "Image Viewer" here -- and a list with the same word twice is a coin
        # toss. The id is what tells them apart.
        seen: dict[str, int] = {}
        for c in candidates:
            seen[c["name"]] = seen.get(c["name"], 0) + 1
        for c in candidates:
            c["ambiguous"] = seen[c["name"]] > 1
        chosen = [d for d in per_type.values() if d]
        distinct = sorted(set(chosen))
        groups.append({
            "key": group["key"],
            "name": group["name"],
            "icon": group["icon"],
            "types": group["types"],
            "perType": per_type,
            # The whole point of grouping: one application for the category, or a
            # split that nobody asked for.
            "agreed": len(distinct) <= 1,
            "current": distinct[0] if len(distinct) == 1 else "",
            "missing": [t for t, d in per_type.items() if not d],
            "candidates": candidates,
        })
    return {"groups": groups}


def set_group(key: str, entry_id: str) -> dict:
    group = next((g for g in GROUPS if g["key"] == key), None)
    if group is None:
        return {"error": f"no such group: {key}"}
    entries = read_entries()
    if entry_id not in entries:
        return {"error": f"no such application: {entry_id}"}
    # Set only the types that application actually declares. Forcing the rest
    # would write an association that fails the moment somebody uses it.
    wanted = [t for t in group["types"] if t in entries[entry_id]["types"]]
    if not wanted:
        return {"error": f"{entry_id} declares none of the types in {key}"}
    subprocess.run(["xdg-mime", "default", entry_id] + wanted, check=False, timeout=15)
    return {"group": key, "application": entry_id, "types": wanted}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("report")
    setter = sub.add_parser("set")
    setter.add_argument("group")
    setter.add_argument("application")
    args = parser.parse_args()
    payload = report() if args.command == "report" else set_group(args.group, args.application)
    json.dump(payload, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
