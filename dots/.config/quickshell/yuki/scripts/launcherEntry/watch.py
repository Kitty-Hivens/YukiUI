#!/usr/bin/env python3
"""Prints what applications announce for their dock buttons.

Applications that want a count, a progress bar or attention on their launcher
broadcast com.canonical.Unity.LauncherEntry.Update on the session bus: Telegram
its unread count, Firefox its downloads. This only listens. It prints one JSON
object per line, the application's desktop id and whichever of the values the
signal carried, and a line with "gone" when the application leaves the bus, so
a badge does not outlive the program that set it.

It stops when its standard input closes. The shell holds the other end, so a
shell that is killed or restarted takes this with it instead of leaving it
running with nobody reading.
"""

import json
import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402  (must follow require_version)

KINDS = {
    "count": int,
    "count-visible": bool,
    "progress": float,
    "progress-visible": bool,
    "urgent": bool,
}

# Which applications each bus connection has spoken for.
speakers = {}


def desktop_id(uri):
    if uri.startswith("application://"):
        uri = uri[len("application://"):]
    if uri.endswith(".desktop"):
        uri = uri[: -len(".desktop")]
    return uri


def emit(message):
    print(json.dumps(message), flush=True)


def on_update(_connection, sender, _path, _interface, _signal, parameters, _data):
    try:
        uri, properties = parameters.unpack()
    except (TypeError, ValueError):
        return
    app = desktop_id(uri)
    if not app:
        return
    message = {"app": app}
    for key, kind in KINDS.items():
        if key in properties:
            try:
                message[key] = kind(properties[key])
            except (TypeError, ValueError):
                pass
    speakers.setdefault(sender, set()).add(app)
    emit(message)


def on_owner_changed(_connection, _sender, _path, _interface, _signal, parameters, _data):
    name, _old, new = parameters.unpack()
    if new == "" and name in speakers:
        for app in speakers.pop(name):
            emit({"app": app, "gone": True})


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.signal_subscribe(None, "com.canonical.Unity.LauncherEntry", "Update", None, None,
                         Gio.DBusSignalFlags.NONE, on_update, None)
    bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                         "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE, on_owner_changed, None)
    loop = GLib.MainLoop()
    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
                      lambda fd, condition: stdin_event(condition, loop))
    loop.run()


def stdin_event(condition, loop):
    # Nothing is ever sent on it, so anything but more to read is the end.
    if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR) or not sys.stdin.buffer.read1(4096):
        loop.quit()
        return False
    return True


if __name__ == "__main__":
    main()
