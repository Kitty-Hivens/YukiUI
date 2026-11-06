#!/usr/bin/env python3
"""The clipboard history every environment reads, with every form kept.

    history.py store          what was just copied, run by wl-paste --watch
    history.py offer ID       an entry back on the clipboard, every form of it
    history.py pin ID 0|1     kept past the limit and through clearing, or not
    history.py delete ID
    history.py clear          everything not pinned
    history.py list           id and a line of each entry, for a menu outside the shell

Each entry keeps the forms it was copied in: the picture, the files, the text,
and the same text marked up. Pasted from the history it goes back on in all of
them, so files copied in the file manager paste as files again and not as
their names. cliphist keeps one form, and its files came back as text.

A copy a password manager marks as secret is never kept. Nor is anything past
the size below, or anything but the forms named here. The pinned entries are
kept, and the newest of the rest, as many as fit both limits below.

Kept in the state folder, readable by the person alone. index.json lists the
entries newest first, for the shell to show: id, when, kind, a preview, pinned
and the forms, and the paths of what files it holds.
"""

import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from urllib.parse import unquote

STATE = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
FOLDER = os.path.join(STATE, "yuki", "clipboard")
INDEX = os.path.join(FOLDER, "index.json")
LIMIT = 750
ALL_TOGETHER = 1024 * 1024 * 1024
MOST = 32 * 1024 * 1024
# Offered back with an entry, so the copy it makes is known for that entry
# coming back rather than for a new one.
MARK = "application/x-yuki-history-id"

IMAGES = ["image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp"]
FILES = ["text/uri-list", "x-special/gnome-copied-files"]
TEXTS = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"]
MARKUP = ["text/html"]


def paste(kind):
    result = subprocess.run(["wl-paste", "--no-newline", "--type", kind], capture_output=True, timeout=10)
    return result.stdout if result.returncode == 0 else None


def read_index():
    try:
        with open(INDEX) as file:
            return json.load(file)
    except (OSError, ValueError):
        return []


def write_index(entries):
    temporary = INDEX + ".new"
    with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as file:
        json.dump(entries, file, ensure_ascii=False)
    os.replace(temporary, INDEX)


def entry_folder(entry_id):
    # Only digits ever name an entry, so nothing given can reach outside.
    if not str(entry_id).isdigit():
        sys.exit(f"history.py: no entry {entry_id!r}")
    return os.path.join(FOLDER, str(entry_id))


def size_of(entry):
    """What an entry takes on disk. Told by the entry, or found for one older than that."""
    if "size" in entry:
        return entry["size"]
    total = 0
    for form in entry.get("forms", []):
        try:
            total += os.path.getsize(form["file"])
        except OSError:
            pass
    return total


def prune(entries):
    kept, unpinned, together = [], 0, 0
    for entry in entries:
        if not entry.get("pinned"):
            unpinned += 1
            together += size_of(entry)
            if unpinned > LIMIT or together > ALL_TOGETHER:
                shutil.rmtree(entry_folder(entry["id"]), ignore_errors=True)
                continue
        kept.append(entry)
    return kept


def paths_of(forms):
    """The local paths in a copy of files, for what goes by the path alone."""
    links = forms.get("text/uri-list") or b""
    found = []
    for line in links.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line.startswith("file://"):
            found.append(unquote(line[len("file://"):]))
    return found


def image_form(data):
    """The form a picture is in, by how it starts, or None for anything else."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"GIF8"):
        return "image/gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data.startswith(b"BM"):
        return "image/bmp"
    return None


def preview_of(kind, forms):
    if kind == "files":
        links = forms.get("text/uri-list") or b""
        names = []
        for line in links.decode("utf-8", "replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                names.append(os.path.basename(line.rstrip("/")))
        return "\n".join(unquote(name) for name in names[:6])
    if kind == "text":
        text = next((forms[t] for t in TEXTS if t in forms), b"").decode("utf-8", "replace")
        return text[:400]
    return ""


def store(handed=b""):
    state = os.environ.get("CLIPBOARD_STATE", "data")
    if state != "data":
        return
    listing = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=10)
    if listing.returncode != 0:
        return
    offered = listing.stdout.split()
    # Marked secret by a password manager, KeePassXC and the like.
    if "x-kde-passwordManagerHint" in offered:
        return

    with lock():
        entries = read_index()
        if MARK in offered:
            back = (paste(MARK) or b"").decode()
            for entry in entries:
                if entry["id"] == back:
                    entries.remove(entry)
                    entry["time"] = time.time()
                    entries.insert(0, entry)
                    write_index(entries)
                    return

        forms = {}
        image = next((t for t in IMAGES if t in offered), None)
        wanted = ([image] if image else []) + [t for t in FILES + TEXTS + MARKUP if t in offered]
        total = 0
        for kind in wanted:
            # A picture wl-paste has handed over already is not asked for again:
            # a Qt program encodes it anew for every request, on its main thread,
            # and copying a photo froze it for as long as that took.
            data = handed if kind == image and image_form(handed) == kind else paste(kind)
            if not data or total + len(data) > MOST:
                continue
            forms[kind] = data
            total += len(data)
        if not forms:
            return
        kind = "image" if image in forms else "files" if "text/uri-list" in forms else "text"
        if kind == "text" and not any(t in forms for t in TEXTS):
            return

        digest = hashlib.sha256()
        for name in sorted(forms):
            digest.update(name.encode() + b"\0" + forms[name])
        digest = digest.hexdigest()
        # The same thing copied again comes back to the top, once.
        for entry in entries:
            if entry.get("digest") == digest:
                entries.remove(entry)
                entry["time"] = time.time()
                entries.insert(0, entry)
                write_index(entries)
                return

        entry_id = str(time.time_ns())
        folder = entry_folder(entry_id)
        os.makedirs(folder, mode=0o700)
        listed = []
        for number, (name, data) in enumerate(forms.items()):
            path = os.path.join(folder, f"form-{number}")
            with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as file:
                file.write(data)
            listed.append({"type": name, "file": path})
        entries.insert(0, {
            "id": entry_id,
            "time": time.time(),
            "kind": kind,
            "preview": preview_of(kind, forms),
            "image": listed[0]["file"] if kind == "image" else "",
            "pinned": False,
            "digest": digest,
            "size": total,
            "paths": paths_of(forms),
            "forms": listed,
        })
        write_index(prune(entries))


def find(entries, entry_id):
    for entry in entries:
        if entry["id"] == entry_id:
            return entry
    sys.exit(f"history.py: no entry {entry_id!r}")


def offer(entry_id):
    entry = find(read_index(), entry_id)
    helper = os.environ.get("YUKI_CLIP") or "/usr/lib/yuki/yuki-clip"
    if os.access(helper, os.X_OK):
        command = [helper]
        for form in entry["forms"]:
            command += ["-f", form["type"], form["file"]]
        command += ["-t", MARK, entry_id]
        sys.exit(subprocess.run(command).returncode)
    first = entry["forms"][0]
    with open(first["file"], "rb") as file:
        sys.exit(subprocess.run(["wl-copy", "--type", first["type"]], stdin=file).returncode)


def pin(entry_id, pinned):
    with lock():
        entries = read_index()
        find(entries, entry_id)["pinned"] = pinned
        write_index(prune(entries))


def delete(entry_id):
    with lock():
        entries = read_index()
        entries.remove(find(entries, entry_id))
        shutil.rmtree(entry_folder(entry_id), ignore_errors=True)
        write_index(entries)


def listing():
    for entry in read_index():
        line = " ".join(entry.get("preview", "").split()) or f"[{entry.get('kind', '')}]"
        print(f"{entry['id']}\t{line}")


def clear():
    with lock():
        entries = read_index()
        for entry in entries:
            if not entry.get("pinned"):
                shutil.rmtree(entry_folder(entry["id"]), ignore_errors=True)
        write_index([entry for entry in entries if entry.get("pinned")])


class lock:
    """One change to the history at a time: copies can come quickly."""

    def __enter__(self):
        os.makedirs(FOLDER, mode=0o700, exist_ok=True)
        os.chmod(FOLDER, 0o700)
        self.file = open(os.path.join(FOLDER, ".lock"), "w")
        fcntl.flock(self.file, fcntl.LOCK_EX)
        return self

    def __exit__(self, *_):
        fcntl.flock(self.file, fcntl.LOCK_UN)
        self.file.close()


def main():
    command = sys.argv[1:] or [""]
    if command[0] == "store":
        # Read to the end before anything else is asked. A Qt program writes what
        # was copied on its own main thread and does nothing else until it is all
        # taken: with standard input left unread it stood still, and so never
        # answered the forms asked for afterwards, until each request ran out of
        # time. Telegram froze on every photo copied.
        store(sys.stdin.buffer.read())
    elif command[0] == "offer" and len(command) == 2:
        offer(command[1])
    elif command[0] == "pin" and len(command) == 3:
        pin(command[1], command[2] == "1")
    elif command[0] == "delete" and len(command) == 2:
        delete(command[1])
    elif command[0] == "clear":
        clear()
    elif command[0] == "list":
        listing()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
