#!/usr/bin/env python3
"""Talks to the OpenTabletDriver daemon for the tablet settings page.

The daemon answers JSON-RPC on a local socket, the same channel its own window
uses. Its console client prints settings as prose, and the digitizer's size,
which a tablet area is measured against, it does not print at all.

Usage:
    otd.py state
        Prints one JSON object: whether the driver is installed and its daemon
        answered, the tablets it drives with what each can do, and its
        settings as it holds them.
    otd.py apply <tablet> <changes json>
        Changes one tablet's profile, hands the result to the daemon and
        writes it where the daemon reads its settings at start. Keys of the
        changes object: "outputMode" (the mode's full type name),
        "displayArea" and "tabletArea" ({Width, Height, X, Y, Rotation}),
        "tipThreshold" (percent of full pressure).

The daemon applies what it is handed but does not keep it: its own window
writes the settings file itself, and so does this. Nothing here asks the
daemon about updates or plugins.
"""

import json
import os
import shutil
import socket
import sys
import tempfile

TIMEOUT = 3.0


def socket_path():
    explicit = os.environ.get("YUKI_OTD_SOCKET")
    if explicit:
        return explicit
    # Where .NET puts a named pipe on Linux: the temporary directory.
    return os.path.join(os.environ.get("TMPDIR") or "/tmp", "CoreFxPipe_OpenTabletDriver.Daemon")


def settings_path():
    explicit = os.environ.get("YUKI_OTD_SETTINGS")
    if explicit:
        return explicit
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(config, "OpenTabletDriver", "settings.json")


class Daemon:
    """One connection, header-delimited JSON-RPC as StreamJsonRpc speaks it."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(TIMEOUT)
        self.sock.connect(socket_path())
        self.buffer = b""
        self.next_id = 1

    def close(self):
        self.sock.close()

    def _read_message(self):
        while b"\r\n\r\n" not in self.buffer:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("the daemon closed the connection")
            self.buffer += chunk
        head, self.buffer = self.buffer.split(b"\r\n\r\n", 1)
        length = None
        for line in head.split(b"\r\n"):
            name, _, value = line.partition(b":")
            if name.strip().lower() == b"content-length":
                length = int(value.strip())
        if length is None:
            raise ConnectionError("a message without a length")
        while len(self.buffer) < length:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("the daemon closed the connection")
            self.buffer += chunk
        body, self.buffer = self.buffer[:length], self.buffer[length:]
        return json.loads(body)

    def call(self, method, *params):
        ident = self.next_id
        self.next_id += 1
        body = json.dumps({"jsonrpc": "2.0", "id": ident, "method": method, "params": list(params)}).encode()
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        # The daemon greets and logs over the same channel, as notifications
        # without an id. Only the answer to this call is wanted.
        while True:
            message = self._read_message()
            if message.get("id") != ident:
                continue
            if "error" in message:
                raise RuntimeError(message["error"].get("message", "the daemon refused"))
            return message.get("result")


def describe(tablet):
    properties = tablet.get("Properties") or {}
    specs = properties.get("Specifications") or {}
    digitizer = specs.get("Digitizer") or {}
    pen = specs.get("Pen") or {}
    aux = specs.get("AuxiliaryButtons") or {}
    return {
        "name": properties.get("Name", ""),
        "width": digitizer.get("Width", 0),
        "height": digitizer.get("Height", 0),
        "maxPressure": pen.get("MaxPressure", 0),
        "penButtons": pen.get("ButtonCount", 0),
        "auxButtons": aux.get("ButtonCount", 0),
    }


def state():
    installed = shutil.which("otd-daemon") is not None
    try:
        daemon = Daemon()
    except OSError:
        return {"installed": installed, "running": False, "tablets": [], "settings": None}
    try:
        tablets = [describe(tablet) for tablet in daemon.call("GetTablets") or []]
        settings = daemon.call("GetSettings")
    finally:
        daemon.close()
    return {"installed": installed, "running": True, "tablets": tablets, "settings": settings}


def area(value):
    return {key: float(value.get(key, 0)) for key in ("Width", "Height", "X", "Y", "Rotation")}


def changed(settings, tablet, changes):
    profile = next((p for p in settings.get("Profiles") or [] if p.get("Tablet") == tablet), None)
    if profile is None:
        raise RuntimeError(f"no profile for {tablet}")
    if "outputMode" in changes:
        mode = profile.setdefault("OutputMode", {})
        # Another mode's settings mean nothing to this one.
        if mode.get("Path") != changes["outputMode"]:
            mode["Settings"] = []
        mode["Path"] = changes["outputMode"]
        mode["Enable"] = True
    absolute = profile.setdefault("AbsoluteModeSettings", {})
    if "displayArea" in changes:
        absolute["Display"] = area(changes["displayArea"])
    if "tabletArea" in changes:
        absolute["Tablet"] = area(changes["tabletArea"])
    if "tipThreshold" in changes:
        profile.setdefault("Bindings", {})["TipActivationThreshold"] = max(0.0, min(100.0, float(changes["tipThreshold"])))
    return settings


def write_settings(settings):
    path = settings_path()
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    # Whole or not at all: the daemon reads this at start, and half a file
    # would leave it on its defaults.
    handle, temporary = tempfile.mkstemp(dir=folder, prefix=".settings-", suffix=".json")
    try:
        with os.fdopen(handle, "w") as out:
            json.dump(settings, out, indent=2)
            out.write("\n")
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def apply(tablet, changes):
    daemon = Daemon()
    try:
        settings = changed(daemon.call("GetSettings"), tablet, changes)
        daemon.call("SetSettings", settings)
    finally:
        daemon.close()
    write_settings(settings)
    return settings


def main(argv):
    if len(argv) >= 2 and argv[1] == "state":
        print(json.dumps(state()))
        return 0
    if len(argv) == 4 and argv[1] == "apply":
        try:
            apply(argv[2], json.loads(argv[3]))
        except (OSError, RuntimeError, ValueError) as error:
            print(str(error), file=sys.stderr)
            return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
