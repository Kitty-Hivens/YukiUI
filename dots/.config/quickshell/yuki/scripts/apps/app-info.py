#!/usr/bin/env python3
"""What the settings show of one application, and the changes they make to it.

    app-info.py info <desktop id>              -> JSON on stdout
    app-info.py autostart <desktop id> on|off

`info` says where the entry's file is, what installed it and what taking it
off would remove, whether it starts with the session, and which kinds of files
it says it opens. Nothing here needs root: removing a package is done by the
caller, through pkexec, with what this reported.
"""

from __future__ import annotations

import configparser
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def data_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    rest = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [home] + [Path(entry) for entry in rest.split(":") if entry]


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def find_entry(entry_id: str) -> Path | None:
    """The file a desktop id names, the first in the data directories, as the
    desktop looks them up. A dash in the id may stand for a subdirectory."""
    name = entry_id if entry_id.endswith(".desktop") else f"{entry_id}.desktop"
    for base in data_dirs():
        applications = base / "applications"
        direct = applications / name
        if direct.is_file():
            return direct
        parts = name.split("-")
        for split in range(1, len(parts)):
            nested = applications.joinpath(*parts[:split], "-".join(parts[split:]))
            if nested.is_file():
                return nested
    return None


def read_entry(path: Path) -> configparser.SectionProxy | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return None
    return parser["Desktop Entry"] if parser.has_section("Desktop Entry") else None


def run(*command: str) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, timeout=20)


def pacman_info(path: Path) -> dict | None:
    owner = run("pacman", "-Qoq", str(path))
    if owner.returncode != 0 or not owner.stdout.strip():
        return None
    package = owner.stdout.strip().splitlines()[0]
    info = {"origin": "pacman", "package": package, "version": "", "size": "", "removes": [], "blocked": ""}
    details = run("pacman", "-Qi", package)
    for line in details.stdout.splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "Version":
            info["version"] = value.strip()
        elif key.strip() == "Installed Size":
            info["size"] = value.strip()
    # What removing it with the dependencies nothing else needs would take.
    # Refused when something else depends on it, which is said as it is.
    plan = run("pacman", "-Rsp", "--print-format", "%n", package)
    if plan.returncode == 0:
        info["removes"] = [name for name in plan.stdout.split() if name]
    else:
        said = plan.stdout + plan.stderr
        needed = ", ".join(dict.fromkeys(re.findall(r"required by (\S+)", said)))
        last = (plan.stderr.strip().splitlines() or ["?"])[-1]
        info["blocked"] = needed or last
    return info


def flatpak_info(path: Path, entry_id: str) -> dict | None:
    text = str(path)
    if "/flatpak/exports/" not in text:
        return None
    app = entry_id.removesuffix(".desktop")
    installation = "user" if text.startswith(str(Path.home())) else "system"
    info = {"origin": "flatpak", "package": app, "installation": installation, "version": "", "size": "", "removes": [app], "blocked": ""}
    details = run("flatpak", "info", f"--{installation}", app)
    for line in details.stdout.splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "Version":
            info["version"] = value.strip()
        elif key.strip() == "Installed Size":
            info["size"] = value.strip()
    return info


def steam_info(entry: configparser.SectionProxy) -> dict | None:
    found = re.search(r"steam://rungameid/(\d+)", entry.get("Exec", ""))
    if not found:
        return None
    return {"origin": "steam", "package": found.group(1), "version": "", "size": "", "removes": [], "blocked": ""}


def autostart_file(entry_id: str) -> Path:
    name = entry_id if entry_id.endswith(".desktop") else f"{entry_id}.desktop"
    return config_home() / "autostart" / name


def starts_with_session(entry_id: str) -> bool:
    """Whether the session starts it: a file of its name in the user's autostart
    folder, or else in the system's, and not hidden or switched off there."""
    name = autostart_file(entry_id).name
    candidates = [config_home() / "autostart" / name]
    candidates += [Path(base) / "autostart" / name for base in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if base]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        entry = read_entry(candidate)
        if entry is None:
            return False
        hidden = entry.get("Hidden", "false").lower() == "true"
        disabled = entry.get("X-GNOME-Autostart-enabled", "true").lower() == "false"
        return not hidden and not disabled
    return False


def set_autostart(entry_id: str, on: bool) -> int:
    path = find_entry(entry_id)
    target = autostart_file(entry_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    if on:
        if path is None:
            print(f"no desktop entry named {entry_id}", file=sys.stderr)
            return 1
        # A copy of the entry, so it starts the way the launcher starts it.
        text = path.read_text(encoding="utf-8", errors="replace")
        text = re.sub(r"^(Hidden|X-GNOME-Autostart-enabled)=.*\n?", "", text, flags=re.MULTILINE)
        target.write_text(text, encoding="utf-8")
        return 0
    # Off. A file of the user's own goes. One the system puts there is
    # overridden by a hidden one of the same name, as the specification has it.
    target.unlink(missing_ok=True)
    if starts_with_session(entry_id):
        target.write_text(f"[Desktop Entry]\nType=Application\nName={entry_id}\nHidden=true\n", encoding="utf-8")
    return 0


def info(entry_id: str) -> dict:
    path = find_entry(entry_id)
    answer = {"id": entry_id, "path": str(path) if path else "", "origin": "none", "package": "", "version": "",
              "size": "", "removes": [], "blocked": "", "autostart": starts_with_session(entry_id), "mimeTypes": []}
    if path is None:
        return answer
    entry = read_entry(path)
    if entry is not None:
        answer["mimeTypes"] = [kind for kind in entry.get("MimeType", "").split(";") if kind]
    found = flatpak_info(path, entry_id) or pacman_info(path) or (steam_info(entry) if entry is not None else None)
    if found:
        answer.update(found)
    elif str(path).startswith(str(Path.home())):
        answer["origin"] = "user"
    return answer


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[1] == "info":
        print(json.dumps(info(argv[2])))
        return 0
    if len(argv) == 4 and argv[1] == "autostart" and argv[3] in ("on", "off"):
        return set_autostart(argv[2], argv[3] == "on")
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
