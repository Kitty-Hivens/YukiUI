#!/usr/bin/env python3
"""Entry point for the yuki xdg-desktop-portal backend.

One process owns the bus name and every yuki interface hangs off the one object
path. Each interface is a module of its own that registers itself here, so this
file only owns the name and runs the loop. It is what the D-Bus activation service
points Exec at.
"""

import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402  (must follow require_version)

import filechooser  # noqa: E402
import wallpaper  # noqa: E402
from common import make_log  # noqa: E402

BUS_NAME = "org.freedesktop.impl.portal.desktop.yuki"

log = make_log("yuki-portal")


def main():
    loop = GLib.MainLoop()

    def on_bus_acquired(connection, name):
        # A warning if the wallpaper switch is missing, never a gate: the file
        # chooser rides the same process and must come up regardless.
        wallpaper.preflight()
        # Register each interface on its own so a failure in one does not take the
        # other down. The file chooser is the one that must not be lost.
        try:
            filechooser.register(connection)
        except GLib.Error as error:
            log(f"cannot export the file chooser: {error.message}")
            loop.quit()
            return
        try:
            wallpaper.register(connection)
        except GLib.Error as error:
            log(f"cannot export the wallpaper interface: {error.message}")

    def on_name_lost(connection, name):
        log(f"cannot own {name}, is another backend running?")
        loop.quit()

    Gio.bus_own_name(
        Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
        on_bus_acquired, None, on_name_lost,
    )
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
