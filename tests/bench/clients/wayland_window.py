#!/usr/bin/env python3
"""A Wayland window the tests drive, through GTK 4.

    wayland_window.py APP_ID TITLE WIDTH HEIGHT [maximized]

With "maximized" it asks to be maximised before it is first shown, as an
application that remembers being maximised does.

Prints {"ready": true} once the window is shown, then answers one command a
line on stdin with one line of JSON:

    maximize, unmaximize       ask to be maximised or put back, as a title bar
                               button does
    minimize                   ask to be minimised
    fullscreen, unfullscreen   ask for fullscreen or to leave it
    state                      what the window believes of itself
    keys                       the keys it has been given since last asked,
                               with the modifiers held, and forgets them
    clicks                     how many presses of a mouse button reached it
                               since last asked, and forgets them
    close                      close the window and end

Everything it asks for goes to the compositor as an xdg_toplevel request, the
way any GTK application asks.
"""

import json
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

app_id, title, width, height = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
start_maximized = sys.argv[5:6] == ["maximized"]

# Several windows of the same id may run at once, each a process of its own.
app = Gtk.Application(application_id=app_id, flags=Gio.ApplicationFlags.NON_UNIQUE)
window = None


def answer(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def state():
    # The states the compositor last sent, as GDK names them: maximized,
    # tiled-left and so on.
    surface = window.get_surface()
    toplevel = list(surface.get_state().value_nicks) if surface else []
    return {
        "maximized": window.is_maximized(),
        "fullscreen": window.is_fullscreen(),
        "width": window.get_width(),
        "height": window.get_height(),
        "toplevel": sorted(toplevel),
    }


def command(channel, condition):
    line = sys.stdin.readline()
    if not line:
        app.quit()
        return False
    try:
        return run(line.strip())
    except Exception as error:  # an answer either way, or the test waits for one
        answer({"error": repr(error)})
        return True


# What reached the window from the keyboard: [pressed or released, key, modifiers].
keys = []


def on_key(kind):
    def record(_controller, keyval, _keycode, modifiers):
        names = [name for name, mask in (("shift", Gdk.ModifierType.SHIFT_MASK), ("control", Gdk.ModifierType.CONTROL_MASK),
                                         ("alt", Gdk.ModifierType.ALT_MASK), ("super", Gdk.ModifierType.SUPER_MASK)) if modifiers & mask]
        keys.append([kind, Gdk.keyval_name(keyval), names])
        return False
    return record


# Presses of a mouse button that reached the window.
clicks = 0


def on_click(_gesture, _count, _x, _y):
    global clicks
    clicks += 1


def run(name):
    if name == "state":
        answer(state())
    elif name == "keys":
        answer({"keys": keys[:]})
        keys.clear()
    elif name == "clicks":
        global clicks
        answer({"clicks": clicks})
        clicks = 0
    elif name in ("maximize", "unmaximize", "minimize", "fullscreen", "unfullscreen"):
        getattr(window, name)()
        answer({"ok": name})
    elif name == "close":
        answer({"ok": name})
        app.quit()
        return False
    else:
        answer({"error": f"unknown command {name}"})
    return True


def on_activate(application):
    global window
    window = Gtk.ApplicationWindow(application=application, title=title)
    window.set_default_size(width, height)
    window.set_titlebar(Gtk.HeaderBar())
    window.set_child(Gtk.Label(label=title))
    controller = Gtk.EventControllerKey()
    controller.connect("key-pressed", on_key("pressed"))
    controller.connect("key-released", on_key("released"))
    window.add_controller(controller)
    gesture = Gtk.GestureClick()
    gesture.set_button(0)
    gesture.connect("pressed", on_click)
    window.add_controller(gesture)
    if start_maximized:
        window.maximize()
    window.connect("map", lambda _window: GLib.idle_add(lambda: answer({"ready": True}) or False))
    window.present()
    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, command)


app.connect("activate", on_activate)
app.run([])
