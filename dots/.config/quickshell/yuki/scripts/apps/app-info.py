#!/usr/bin/env python3
"""What the settings show of one application, and the changes they make to it.

    app-info.py info <desktop id>              -> JSON on stdout
    app-info.py autostart <desktop id> on|off

`info` says where the entry's file is, what installed it and what taking it
off would remove, whether it starts with the session, and which kinds of files
it says it opens. Nothing here needs root: removing a package is done by the
caller, through pkexec, with what this reported.

A desktop id is the entry's file name without .desktop, a file in a
subdirectory of applications/ named with its path joined by dashes, as
Quickshell and the specification name them. An id may itself end in
".desktop": Telegram's is org.telegram.desktop.
"""

from __future__ import annotations

import configparser
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()


def data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")


def data_dirs() -> list[Path]:
    rest = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [data_home()] + [Path(entry) for entry in rest.split(":") if entry]


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")


def config_dirs() -> list[Path]:
    return [Path(base) for base in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if base]


def file_name(entry_id: str) -> str:
    return f"{entry_id}.desktop"


def under(path: Path, folder: Path) -> bool:
    try:
        path.relative_to(folder)
        return True
    except ValueError:
        return False


def entries_named(entry_id: str) -> list[Path]:
    """Every file the id names, the one in use first, then those it shadows."""
    name = file_name(entry_id)
    found = []
    for base in data_dirs():
        applications = base / "applications"
        direct = applications / name
        if direct.is_file():
            found.append(direct)
            continue
        if "-" not in entry_id or not applications.is_dir():
            continue
        # A subdirectory's entry: its relative path with the slashes as dashes.
        for candidate in applications.rglob("*.desktop"):
            if candidate.parent != applications and "-".join(candidate.relative_to(applications).parts) == name:
                found.append(candidate)
                break
    return found


def find_entry(entry_id: str) -> Path | None:
    found = entries_named(entry_id)
    return found[0] if found else None


def read_entry(path: Path) -> configparser.SectionProxy | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return None
    return parser["Desktop Entry"] if parser.has_section("Desktop Entry") else None


def run(*command: str) -> subprocess.CompletedProcess:
    """A command's answer, or exit status 127 with nothing said when it is not
    there to ask, on a system without pacman or flatpak say."""
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as error:
        return subprocess.CompletedProcess(command, 127, "", str(error))


def entry_names(paths: list[str]) -> list[str]:
    names = []
    for path in paths:
        entry = read_entry(Path(path))
        if entry is not None and entry.get("NoDisplay", "false").lower() != "true":
            names.append(entry.get("Name", Path(path).stem))
    return names


def pacman_info(path: Path) -> dict | None:
    owner = run("pacman", "-Qoq", str(path))
    if owner.returncode != 0 or not owner.stdout.strip():
        return None
    package = owner.stdout.strip().splitlines()[0]
    info = {"origin": "pacman", "package": package, "version": "", "size": "", "removes": [], "blocked": "", "alsoApps": []}
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
    # The other applications the same packages bring, which go with them.
    files = run("pacman", "-Qlq", *(info["removes"] or [package]))
    others = [line for line in files.stdout.splitlines()
              if re.match(r"^/usr/share/applications/.+\.desktop$", line) and line != str(path)]
    info["alsoApps"] = entry_names(others)
    return info


def flatpak_info(path: Path, entry: configparser.SectionProxy | None) -> dict | None:
    if "/flatpak/exports/" not in str(path):
        return None
    # The application an exported entry belongs to: one application may export
    # several entries, LibreOffice one per program, each with an id of its own.
    app = (entry.get("X-Flatpak", "") if entry is not None else "") or path.stem
    installation = "user" if under(path, HOME) else "system"
    info = {"origin": "flatpak", "package": app, "installation": installation, "version": "", "size": "",
            "removes": [app], "blocked": "", "alsoApps": [], "dataFolder": str(HOME / ".var/app" / app)}
    details = run("flatpak", "info", f"--{installation}", app)
    for line in details.stdout.splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "Version":
            info["version"] = value.strip()
        elif key.strip() == "Installed Size":
            info["size"] = value.strip()
    info["hasData"] = (HOME / ".var/app" / app).is_dir()
    return info


def steam_info(entry: configparser.SectionProxy) -> dict | None:
    found = re.search(r"steam://rungameid/(\d+)", entry.get("Exec", ""))
    if not found:
        return None
    return {"origin": "steam", "package": found.group(1), "version": "", "size": "", "removes": [], "blocked": ""}


def autostart_file(entry_id: str) -> Path:
    return config_home() / "autostart" / file_name(entry_id)


def system_autostart(entry_id: str) -> Path | None:
    for base in config_dirs():
        candidate = base / "autostart" / file_name(entry_id)
        if candidate.is_file():
            return candidate
    return None


def shown_here(entry: configparser.SectionProxy) -> bool:
    """Whether an autostart entry is one this session starts: not kept to other
    desktops, and its program there if it names one to try."""
    desktops = {name for name in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if name}
    only = {name for name in entry.get("OnlyShowIn", "").split(";") if name}
    never = {name for name in entry.get("NotShowIn", "").split(";") if name}
    if only and not (only & desktops):
        return False
    if never & desktops:
        return False
    tried = entry.get("TryExec", "")
    if tried and not (os.path.isabs(tried) and os.access(tried, os.X_OK)) and not any(
            os.access(os.path.join(folder, tried), os.X_OK) for folder in os.environ.get("PATH", "").split(":") if folder):
        return False
    return True


def starts_with_session(entry_id: str) -> bool:
    """Whether the session starts it: the user's autostart file of its name, or
    else the system's, not hidden or switched off and meant for this desktop."""
    for candidate in [autostart_file(entry_id), system_autostart(entry_id)]:
        if candidate is None or not candidate.is_file():
            continue
        entry = read_entry(candidate)
        if entry is None:
            return False
        hidden = entry.get("Hidden", "false").lower() == "true"
        disabled = entry.get("X-GNOME-Autostart-enabled", "true").lower() == "false"
        return not hidden and not disabled and shown_here(entry)
    return False


SWITCHES = re.compile(r"^(Hidden|X-GNOME-Autostart-enabled)\s*=.*\n?", re.MULTILINE)


def set_autostart(entry_id: str, on: bool) -> int:
    target = autostart_file(entry_id)
    system = system_autostart(entry_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    own = target.read_text(encoding="utf-8", errors="replace") if target.is_file() else None
    if on:
        if own is not None:
            # Switched off here, the application's own file or the hidden one
            # over the system's: what turned it off goes, and it starts the
            # way it set itself to, with its own flags, minimised to the tray
            # say. A hidden file over the system's holds nothing else and goes.
            kept = SWITCHES.sub("", own)
            if system is not None and re.fullmatch(r"\s*\[Desktop Entry\]\s*(Type=.*\n|Name=.*\n|\s)*", kept):
                target.unlink()
            else:
                target.write_text(kept, encoding="utf-8")
            return 0
        if system is not None:
            return 0
        path = find_entry(entry_id)
        if path is None:
            print(f"no desktop entry named {entry_id}", file=sys.stderr)
            return 1
        # A copy of the entry, so it starts the way the launcher starts it.
        text = SWITCHES.sub("", path.read_text(encoding="utf-8", errors="replace"))
        target.write_text(text, encoding="utf-8")
        return 0
    # Off, as the specification has it: Hidden in the user's file of the name,
    # the application's own kept as it is otherwise, so switching it back on
    # brings back what it had set.
    path = find_entry(entry_id)
    copy = SWITCHES.sub("", path.read_text(encoding="utf-8", errors="replace")) if path is not None else None
    if own is not None and copy is not None and SWITCHES.sub("", own) == copy and system is None:
        # The copy switching it on made, nothing of the application's own in it.
        target.unlink()
    elif own is not None:
        text = SWITCHES.sub("", own)
        text = re.sub(r"^\[Desktop Entry\][ \t]*\n?", "[Desktop Entry]\nHidden=true\n", text, count=1, flags=re.MULTILINE)
        if "Hidden=true" not in text:
            text = "[Desktop Entry]\nHidden=true\n" + text
        target.write_text(text, encoding="utf-8")
    elif system is not None:
        target.write_text(f"[Desktop Entry]\nType=Application\nName={entry_id}\nHidden=true\n", encoding="utf-8")
    return 0


def info(entry_id: str) -> dict:
    found = entries_named(entry_id)
    path = found[0] if found else None
    answer = {"id": entry_id, "path": str(path) if path else "", "origin": "none", "package": "", "version": "",
              "size": "", "removes": [], "blocked": "", "alsoApps": [], "override": "",
              "autostart": starts_with_session(entry_id), "mimeTypes": []}
    if path is None:
        return answer
    entry = read_entry(path)
    if entry is not None:
        answer["mimeTypes"] = [kind for kind in entry.get("MimeType", "").split(";") if kind]
    # The user's own copy of an entry an installed application brings: what
    # installed it is read from the copy it shadows, and the copy is said apart.
    installed = path
    own_folder = data_home() / "applications"
    if under(path, own_folder) and len(found) > 1:
        answer["override"] = str(path)
        installed = found[1]
        entry = read_entry(installed) or entry
    origin = flatpak_info(installed, entry) or pacman_info(installed) or (steam_info(entry) if entry is not None else None)
    if origin:
        answer.update(origin)
    elif under(installed, own_folder) and os.access(installed.parent, os.W_OK):
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
