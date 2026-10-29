#!/usr/bin/env python3
"""A tray icon for the bench, with a menu of two checkable entries.

    tray_item.py

Registers a StatusNotifierItem on the session bus it is started on, with a
DBusMenu of two entries, "First" checked and "Second" not, both checkmarks, the
way Easy Effects lists its presets. Prints {"ready": true} once registered,
then answers one command a line on stdin:

    pick NAME   checks that entry and unchecks the other, announcing only the
                toggle state that changed, as Easy Effects does
    quit        ends

Each command is answered with {"ok": NAME}.
"""

import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402

ITEM_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <method name="GetLayout">
      <arg type="i" name="parentId" direction="in"/>
      <arg type="i" name="recursionDepth" direction="in"/>
      <arg type="as" name="propertyNames" direction="in"/>
      <arg type="u" name="revision" direction="out"/>
      <arg type="(ia{sv}av)" name="layout" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg type="ai" name="ids" direction="in"/>
      <arg type="as" name="propertyNames" direction="in"/>
      <arg type="a(ia{sv})" name="properties" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" name="id" direction="in"/>
      <arg type="s" name="eventId" direction="in"/>
      <arg type="v" name="data" direction="in"/>
      <arg type="u" name="timestamp" direction="in"/>
    </method>
    <method name="AboutToShow">
      <arg type="i" name="id" direction="in"/>
      <arg type="b" name="needUpdate" direction="out"/>
    </method>
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <signal name="ItemsPropertiesUpdated">
      <arg type="a(ia{sv})" name="updatedProps"/>
      <arg type="a(ias)" name="removedProps"/>
    </signal>
    <signal name="LayoutUpdated">
      <arg type="u" name="revision"/>
      <arg type="i" name="parent"/>
    </signal>
  </interface>
</node>
"""

ENTRIES = {1: "First", 2: "Second"}
checked = {1: True, 2: False}


def answer(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def properties(entry_id):
    return {
        "label": GLib.Variant("s", ENTRIES[entry_id]),
        "toggle-type": GLib.Variant("s", "checkmark"),
        "toggle-state": GLib.Variant("i", 1 if checked[entry_id] else 0),
    }


def layout():
    children = [GLib.Variant("(ia{sv}av)", (entry_id, properties(entry_id), [])) for entry_id in ENTRIES]
    return (0, {"children-display": GLib.Variant("s", "submenu")}, children)


def on_item_property(_connection, _sender, _path, _interface, name):
    values = {
        "Category": GLib.Variant("s", "ApplicationStatus"),
        "Id": GLib.Variant("s", "bench-tray"),
        "Title": GLib.Variant("s", "Bench tray"),
        "Status": GLib.Variant("s", "Active"),
        "IconName": GLib.Variant("s", "battery-good"),
        "ItemIsMenu": GLib.Variant("b", False),
        "Menu": GLib.Variant("o", "/Menu"),
    }
    return values.get(name)


def on_menu_call(_connection, _sender, _path, _interface, method, params, invocation):
    if method == "GetLayout":
        invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, layout())))
    elif method == "GetGroupProperties":
        ids = params.unpack()[0] or list(ENTRIES)
        invocation.return_value(GLib.Variant("(a(ia{sv}))", ([(entry_id, properties(entry_id)) for entry_id in ids if entry_id in ENTRIES],)))
    elif method == "AboutToShow":
        invocation.return_value(GLib.Variant("(b)", (False,)))
    else:
        invocation.return_value(None)


def on_menu_property(_connection, _sender, _path, _interface, name):
    return {"Version": GLib.Variant("u", 3), "Status": GLib.Variant("s", "normal")}.get(name)


bus = Gio.bus_get_sync(Gio.BusType.SESSION)
bus.register_object("/StatusNotifierItem", Gio.DBusNodeInfo.new_for_xml(ITEM_XML).interfaces[0], None, on_item_property, None)
bus.register_object("/Menu", Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0], on_menu_call, on_menu_property, None)
service = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
Gio.bus_own_name_on_connection(bus, service, Gio.BusNameOwnerFlags.NONE, None, None)


def register():
    try:
        bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                      "RegisterStatusNotifierItem", GLib.Variant("(s)", (service,)), None, Gio.DBusCallFlags.NONE, 2000, None)
    except GLib.Error:
        return True  # the watcher is not up yet, try again
    answer({"ready": True})
    return False


def command(channel, condition):
    line = sys.stdin.readline()
    if not line:
        loop.quit()
        return False
    words = line.split()
    if words[:1] == ["pick"] and len(words) == 2:
        picked = next((entry_id for entry_id, text in ENTRIES.items() if text == words[1]), None)
        for entry_id in ENTRIES:
            checked[entry_id] = entry_id == picked
        # Only the toggle state, as Easy Effects announces a change.
        changed = [(entry_id, {"toggle-state": GLib.Variant("i", 1 if checked[entry_id] else 0)}) for entry_id in ENTRIES]
        bus.emit_signal(None, "/Menu", "com.canonical.dbusmenu", "ItemsPropertiesUpdated", GLib.Variant("(a(ia{sv})a(ias))", (changed, [])))
        answer({"ok": words[1]})
    elif words[:1] == ["quit"]:
        answer({"ok": "quit"})
        loop.quit()
        return False
    else:
        answer({"error": f"unknown command {line.strip()}"})
    return True


loop = GLib.MainLoop()
GLib.timeout_add(200, register)
GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, command)
loop.run()
