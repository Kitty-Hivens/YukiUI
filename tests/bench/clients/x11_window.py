#!/usr/bin/env python3
"""An X11 window the tests drive, through python-xlib, under XWayland.

    x11_window.py CLASS TITLE X Y WIDTH HEIGHT

Prints {"ready": true} once the window is mapped, then answers one command a
line on stdin with one line of JSON:

    netstate add|remove|toggle maximized|fullscreen|hidden
                               a _NET_WM_STATE request, as an application's
                               own maximise button or fullscreen key sends it
    iconify, normal            a WM_CHANGE_STATE request, as a minimise button
                               sends it, or the request to be shown again
    configure X Y WIDTH HEIGHT the application placing and sizing itself
    state                      its _NET_WM_STATE and its geometry
    close                      unmap and end

An X11 application can place and size its own window, unlike a Wayland one,
which is what `configure` and the position given at the start are for.
"""

import contextlib
import json
import os
import select
import sys

from Xlib import X, display, protocol

wm_class, title = sys.argv[1], sys.argv[2]
x, y, width, height = (int(value) for value in sys.argv[3:7])

# python-xlib writes its warning about a missing Xauthority to stdout, which is
# where the answers go.
with contextlib.redirect_stdout(sys.stderr):
    connection = display.Display()
screen = connection.screen()
root = screen.root
window = root.create_window(x, y, width, height, 0, screen.root_depth, X.InputOutput, X.CopyFromParent,
                            background_pixel=screen.white_pixel, event_mask=X.StructureNotifyMask)
window.set_wm_name(title)
window.set_wm_class(wm_class, wm_class)
window.change_property(connection.intern_atom("_NET_WM_PID"), connection.intern_atom("CARDINAL"), 32, [os.getpid()])
# Where it asks to be, as an application that remembers its own place does.
window.set_wm_normal_hints(flags=1 | 4, x=x, y=y, width=width, height=height)
window.map()
connection.sync()

STATES = {
    "maximized": ["_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ"],
    "fullscreen": ["_NET_WM_STATE_FULLSCREEN"],
    "hidden": ["_NET_WM_STATE_HIDDEN"],
}
ACTIONS = {"remove": 0, "add": 1, "toggle": 2}


def answer(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def send(atom, data):
    event = protocol.event.ClientMessage(window=window, client_type=connection.intern_atom(atom),
                                         data=(32, (data + [0] * 5)[:5]))
    root.send_event(event, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
    connection.sync()


def state():
    names = []
    prop = window.get_full_property(connection.intern_atom("_NET_WM_STATE"), X.AnyPropertyType)
    for atom in (prop.value if prop else []):
        names.append(connection.get_atom_name(atom))
    geometry = window.get_geometry()
    origin = window.translate_coords(root, 0, 0)
    return {"net_wm_state": names, "geometry": [-origin.x, -origin.y, geometry.width, geometry.height]}


def command(line):
    words = line.split()
    if not words:
        return True
    name = words[0]
    if name == "netstate" and len(words) == 3 and words[1] in ACTIONS and words[2] in STATES:
        atoms = [connection.intern_atom(atom) for atom in STATES[words[2]]]
        send("_NET_WM_STATE", [ACTIONS[words[1]], atoms[0], atoms[1] if len(atoms) > 1 else 0, 1])
        answer({"ok": line})
    elif name == "iconify":
        send("WM_CHANGE_STATE", [3])
        answer({"ok": name})
    elif name == "normal":
        send("WM_CHANGE_STATE", [1])
        answer({"ok": name})
    elif name == "configure" and len(words) == 5:
        cx, cy, cw, ch = (int(value) for value in words[1:])
        window.configure(x=cx, y=cy, width=cw, height=ch)
        connection.sync()
        answer({"ok": name})
    elif name == "state":
        answer(state())
    elif name == "close":
        window.unmap()
        connection.sync()
        answer({"ok": name})
        return False
    else:
        answer({"error": f"unknown command {line}"})
    return True


ready = False
running = True
while running:
    # Events first, so the window stays answered while it waits for commands.
    while connection.pending_events():
        event = connection.next_event()
        if event.type == X.MapNotify and not ready:
            ready = True
            answer({"ready": True})
    readable, _, _ = select.select([sys.stdin, connection.fileno()], [], [], 0.1)
    if sys.stdin in readable:
        line = sys.stdin.readline()
        if not line:
            break
        try:
            running = command(line.strip())
        except Exception as error:  # an answer either way, or the test waits for one
            answer({"error": repr(error)})
