#!/usr/bin/env python3
"""Answers "which backend actually serves this portal interface", and changes it.

xdg-desktop-portal resolves an interface to a backend by walking a preference
list, and it publishes the result nowhere: not on the bus, not in its journal.
So a question as ordinary as "who draws my file chooser" can only be answered by
re-doing the resolution by hand, which is what this does.

Reading is `report`; it prints JSON. Writing is `set`, which edits only the
user's own configuration file and never the packaged ones.
"""

import argparse
import configparser
import json
import os
import sys
from pathlib import Path

PREFIX = "org.freedesktop.impl.portal."
GROUP = "preferred"


def env_list(name: str, fallback: str) -> list[str]:
    raw = os.environ.get(name) or fallback
    # Duplicates are real: a session that prepends to XDG_DATA_DIRS on every
    # import ends up naming the same directory several times, and each one would
    # otherwise contribute the same backend again.
    seen, out = set(), []
    for part in raw.split(":"):
        part = part.strip()
        if part and part not in seen:
            seen.add(part)
            out.append(part)
    return out


def config_dirs() -> list[Path]:
    """Every directory that may hold a portals.conf, highest precedence first."""
    home = Path.home()
    dirs = [Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")]
    dirs += [Path(p) for p in env_list("XDG_CONFIG_DIRS", "/etc/xdg")]
    dirs += [Path("/etc")]
    dirs += [Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")]
    dirs += [Path(p) for p in env_list("XDG_DATA_DIRS", "/usr/local/share:/usr/share")]
    dirs += [Path("/usr/share")]
    out, seen = [], set()
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def desktops() -> list[str]:
    """The desktop names to try, most specific first, lower-cased as the spec asks."""
    raw = os.environ.get("XDG_CURRENT_DESKTOP", "")
    return [name.strip().lower() for name in raw.split(":") if name.strip()]


def ini(path: Path) -> configparser.RawConfigParser:
    # Interface names carry dots and the values carry no interpolation; keys are
    # case sensitive and must not be lower-cased, or every interface name breaks.
    parser = configparser.RawConfigParser(delimiters=("=",), comment_prefixes=("#", ";"))
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    return parser


def find_config() -> tuple[Path | None, list[dict]]:
    """The configuration file in force, and every candidate that was considered.

    The whole list is returned rather than just the winner, because "the file you
    are editing is not the one being read" is the single most common way this
    goes wrong -- a kde-portals.conf sitting in /usr/share looks authoritative
    and never applies outside KDE.
    """
    names = [f"{name}-portals.conf" for name in desktops()] + ["portals.conf"]
    candidates, chosen = [], None
    for directory in config_dirs():
        for name in names:
            path = directory / "xdg-desktop-portal" / name
            exists = path.is_file()
            candidates.append({"path": str(path), "exists": exists, "active": False})
            if exists and chosen is None:
                chosen = path
                candidates[-1]["active"] = True
    return chosen, candidates


def read_backends() -> dict[str, dict]:
    """Every installed backend, by the name the configuration calls it.

    A .portal file's stem is that name: "gtk.portal" is the "gtk" in a preference
    list. Directories are walked lowest precedence first so that a backend found
    in a more important one replaces it.
    """
    found: dict[str, dict] = {}
    roots = [Path(p) / "xdg-desktop-portal" / "portals" for p in env_list("XDG_DATA_DIRS", "/usr/local/share:/usr/share")]
    roots.append(Path("/usr/share/xdg-desktop-portal/portals"))
    for root in reversed(roots):
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.portal")):
            parser = ini(path)
            if not parser.has_section("portal"):
                continue
            raw = parser["portal"].get("Interfaces", "")
            # Stored short. A .portal file spells interfaces out in full while a
            # configuration key is the full name too, but everything else here --
            # the rows, the arguments to `set`, what a person reads -- wants the
            # last component, and mixing the two silently matches nothing.
            interfaces = sorted({
                part.strip()[len(PREFIX):] if part.strip().startswith(PREFIX) else part.strip()
                for part in raw.split(";") if part.strip()
            })
            use_in = [part.strip() for part in parser["portal"].get("UseIn", "").split(";") if part.strip()]
            found[path.stem] = {
                "name": path.stem,
                "path": str(path),
                "dbusName": parser["portal"].get("DBusName", ""),
                "interfaces": interfaces,
                # Deprecated since 1.18 and ignored while a configuration file
                # exists, but still worth showing: a backend that only declares
                # UseIn for another desktop is a common reason one is "missing".
                "useIn": use_in,
            }
    return found


def resolve(interface: str, rules: dict[str, str], backends: dict[str, dict]) -> dict:
    """Who serves one interface, and why -- including who was asked first and passed.

    `skipped` is the point of this: a preference of "hyprland;gtk" resolving to
    gtk is not a misconfiguration, it is hyprland not implementing the interface,
    and nothing anywhere says so.
    """
    key = PREFIX + interface
    explicit = key in rules
    raw = rules.get(key, rules.get("default", ""))
    wanted = [part.strip() for part in raw.split(";") if part.strip()]
    skipped: list[str] = []
    for name in wanted:
        if name == "none":
            return {"backend": "", "disabled": True, "explicit": explicit,
                    "preference": wanted, "skipped": skipped}
        if name == "*":
            for candidate in sorted(backends):
                if interface in backends[candidate]["interfaces"]:
                    return {"backend": candidate, "disabled": False, "explicit": explicit,
                            "preference": wanted, "skipped": skipped, "wildcard": True}
            continue
        backend = backends.get(name)
        if backend is not None and interface in backend["interfaces"]:
            return {"backend": name, "disabled": False, "explicit": explicit,
                    "preference": wanted, "skipped": skipped}
        skipped.append(name if backend is not None else f"{name} (not installed)")
    return {"backend": "", "disabled": False, "explicit": explicit,
            "preference": wanted, "skipped": skipped}


def report() -> dict:
    backends = read_backends()
    path, candidates = find_config()
    rules = dict(ini(path)[GROUP]) if path is not None and ini(path).has_section(GROUP) else {}

    interfaces = {name for backend in backends.values() for name in backend["interfaces"]}
    interfaces |= {key[len(PREFIX):] for key in rules if key.startswith(PREFIX)}

    rows = []
    for interface in sorted(interfaces):
        entry = resolve(interface, rules, backends)
        entry["interface"] = interface
        # Everyone who declares the interface, and no attempt to guess who could
        # actually serve it here. UseIn was tried for that and is a bad signal:
        # xdg-desktop-portal-gtk declares UseIn=gnome and is nevertheless what
        # answers most interfaces on a wlroots session. What separates a backend
        # that works from one that does not -- gtk drawing a dialog by itself
        # against gnome needing org.gnome.Mutter behind it -- is declared nowhere.
        entry["providers"] = sorted(n for n, b in backends.items() if interface in b["interfaces"])
        rows.append(entry)

    return {
        "desktops": desktops(),
        "config": {"active": str(path) if path else "", "candidates": candidates,
                   "writable": str(writable_config())},
        "backends": [backends[name] for name in sorted(backends)],
        "interfaces": rows,
    }


def writable_config() -> Path:
    """Where a change goes: the user's own file for this desktop, never a packaged one."""
    home = Path.home()
    base = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "xdg-desktop-portal"
    names = desktops()
    return base / (f"{names[0]}-portals.conf" if names else "portals.conf")


def set_rule(interface: str, value: str) -> dict:
    """Writes one rule into the user's own config.

    Only the user's own file is touched. If the configuration in force is a
    packaged one, this creates the user file, which then wins -- so the result is
    still that the rule applies, and nothing under /usr was edited.

    The file is rewritten from the parsed document rather than edited in place, so
    comments and blank lines in it do not survive. Every rule does.
    """
    target = writable_config()
    target.parent.mkdir(parents=True, exist_ok=True)
    parser = ini(target) if target.is_file() else ini(Path(os.devnull))
    if not parser.has_section(GROUP):
        parser.add_section(GROUP)
    key = "default" if interface == "default" else PREFIX + interface
    if value:
        parser.set(GROUP, key, value)
    elif parser.has_option(GROUP, key):
        parser.remove_option(GROUP, key)
    temporary = target.with_suffix(target.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        parser.write(handle, space_around_delimiters=False)
    temporary.replace(target)
    return {"written": str(target), "key": key, "value": value}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("report", help="print the resolved mapping as JSON")
    setter = sub.add_parser("set", help="set one preference in the user's own config")
    setter.add_argument("interface", help='interface short name, or "default"')
    setter.add_argument("value", help='semicolon separated backends, "none", or empty to unset')

    args = parser.parse_args()
    if args.command == "report":
        json.dump(report(), sys.stdout, indent=2, sort_keys=False)
        sys.stdout.write("\n")
        return 0
    json.dump(set_rule(args.interface, args.value), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
