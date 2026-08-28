#!/usr/bin/env python3
"""The shell's BlueZ pairing agent.

BlueZ hands every question a pairing raises -- a passkey to compare, a PIN to
type, a stranger asking to connect -- to whichever agent has registered itself
on the system bus, and refuses the pairing outright when none has. Quickshell
can read BlueZ but cannot export a D-Bus object, so the shell cannot be that
agent itself. This process is: it answers org.bluez.Agent1, passes the questions
up on its stdout, and takes the answers back on its stdin.

It is started by the shell and ends with it, which is also what unregisters the
agent -- BlueZ drops an agent whose bus name goes away.

One JSON object per line each way. Up:

    {"event": "ready"}
    {"event": "ask",  "id": 1, "kind": "confirm", "name": ..., "passkey": ...}
    {"event": "show", "id": 2, "kind": "displayPasskey", "passkey": ..., ...}
    {"event": "done", "id": 1, "reason": "canceled"}
    {"event": "error", "message": ...}

Down:

    {"id": 1, "accept": true}
    {"id": 1, "accept": true, "value": "492817"}
    {"id": 1, "accept": false}
"""

import json
import signal
import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402  (must follow require_version)

try:
    gi.require_version("GioUnix", "2.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GioUnix, GLibUnix  # noqa: E402

    unix_input_stream = GioUnix.InputStream.new
    unix_signal_add = GLibUnix.signal_add
except (ImportError, ValueError):
    # Before PyGObject 3.50 the Unix-only pieces still lived in Gio and GLib,
    # where they are now deprecated and warn on every start.
    unix_input_stream = Gio.UnixInputStream.new
    unix_signal_add = GLib.unix_signal_add

BLUEZ = "org.bluez"
BLUEZ_ROOT = "/org/bluez"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
DEVICE_IFACE = "org.bluez.Device1"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"

AGENT_PATH = "/org/yuki/bluetooth/agent"

# The full set. Capability is how BlueZ decides which pairing method two devices
# can agree on, and claiming less than the shell can do would push it down to a
# weaker one -- NoInputNoOutput pairs without asking anything at all.
CAPABILITY = "KeyboardDisplay"

REJECTED = "org.bluez.Error.Rejected"
CANCELED = "org.bluez.Error.Canceled"

PASSKEY_MAX = 999999

# What a device is asking permission to use. Deliberately not translated: these
# are the profiles' own names, the same ones every other bluetooth tool prints,
# and the prompt shows the name beside the raw UUID rather than instead of it.
SERVICE_NAMES = {
    "00001105": "Object Push",
    "00001106": "File Transfer",
    "00001108": "Headset",
    "0000110a": "Audio Source",
    "0000110b": "Audio Sink",
    "0000110c": "Remote Control Target",
    "0000110e": "Remote Control",
    "00001112": "Headset Audio Gateway",
    "0000111e": "Handsfree",
    "0000111f": "Handsfree Audio Gateway",
    "00001124": "Human Interface Device",
    "0000112f": "Phone Book Access",
    "00001132": "Message Access",
    "00001133": "Message Notification",
    "00001200": "Device Identification",
    "0000180f": "Battery",
    "00001812": "Human Interface Device",
}

INTROSPECTION_XML = """
<node>
  <interface name='org.bluez.Agent1'>
    <method name='Release'/>
    <method name='RequestPinCode'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='pincode' direction='out'/>
    </method>
    <method name='DisplayPinCode'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='pincode' direction='in'/>
    </method>
    <method name='RequestPasskey'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='out'/>
    </method>
    <method name='DisplayPasskey'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='in'/>
      <arg type='q' name='entered' direction='in'/>
    </method>
    <method name='RequestConfirmation'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='in'/>
    </method>
    <method name='RequestAuthorization'>
      <arg type='o' name='device' direction='in'/>
    </method>
    <method name='AuthorizeService'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='uuid' direction='in'/>
    </method>
    <method name='Cancel'/>
  </interface>
</node>
"""


class State:
    """What is outstanding right now.

    `pending` holds the D-Bus invocation still waiting on an answer, or None for
    a display, which BlueZ has already been answered for and which only stays
    around so it can be taken off the screen. `displays` maps a device to the
    request already on screen for it, because BlueZ calls DisplayPasskey again
    for every digit typed on the far end and each of those is an update, not a
    second prompt.
    """

    loop = None
    connection = None
    next_id = 0
    pending = {}
    kinds = {}
    devices = {}
    displays = {}


def log(message):
    print(f"[bluetooth-agent] {message}", file=sys.stderr, flush=True)


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def service_name(uuid):
    return SERVICE_NAMES.get(uuid.lower()[:8], "")


def device_properties(connection, path):
    """What the prompt needs in order to name who is asking."""
    try:
        reply = connection.call_sync(
            BLUEZ, path, PROPERTIES_IFACE, "GetAll",
            GLib.Variant("(s)", (DEVICE_IFACE,)), GLib.VariantType("(a{sv})"),
            Gio.DBusCallFlags.NONE, 5000, None,
        )
    except GLib.Error as error:
        # A device can go out of range between asking and being asked about.
        log(f"cannot read {path}: {error.message}")
        return {}
    return reply.unpack()[0]


def describe(connection, path):
    properties = device_properties(connection, path)
    address = properties.get("Address", "")
    return {
        "device": path,
        "name": properties.get("Name") or properties.get("Alias") or address,
        "address": address,
        "icon": properties.get("Icon", ""),
        "paired": bool(properties.get("Paired", False)),
    }


def ask(connection, kind, path, invocation, **extra):
    State.next_id += 1
    request_id = State.next_id
    State.pending[request_id] = invocation
    State.kinds[request_id] = kind
    State.devices[request_id] = path
    emit({"event": "ask", "id": request_id, "kind": kind, **describe(connection, path), **extra})


def show(connection, kind, path, **extra):
    """A number to read off the screen, which BlueZ does not wait for an answer to."""
    request_id = State.displays.get(path)
    if request_id is None:
        State.next_id += 1
        request_id = State.next_id
        State.displays[path] = request_id
        State.pending[request_id] = None
        State.kinds[request_id] = kind
        State.devices[request_id] = path
    emit({"event": "show", "id": request_id, "kind": kind, **describe(connection, path), **extra})


def drop(request_id, reason):
    invocation = State.pending.pop(request_id, None)
    path = State.devices.pop(request_id, "")
    State.kinds.pop(request_id, None)
    if State.displays.get(path) == request_id:
        del State.displays[path]
    if invocation is not None:
        invocation.return_dbus_error(CANCELED, "The request was canceled")
    emit({"event": "done", "id": request_id, "reason": reason})


def drop_all(reason):
    for request_id in list(State.pending):
        drop(request_id, reason)


def trust(connection, path):
    """Saying yes to a pairing is saying yes to the device.

    Left untrusted, every later connection comes back through AuthorizeService
    and asks again about a device the person has already accepted once. Set on
    the answer rather than on the pairing finishing: a pairing that then fails
    leaves the flag on an object BlueZ is about to forget anyway.
    """
    try:
        connection.call_sync(
            BLUEZ, path, PROPERTIES_IFACE, "Set",
            GLib.Variant("(ssv)", (DEVICE_IFACE, "Trusted", GLib.Variant("b", True))),
            None, Gio.DBusCallFlags.NONE, 5000, None,
        )
    except GLib.Error as error:
        log(f"cannot trust {path}: {error.message}")


def passkey_from(value):
    """The six digits BlueZ wants, or None when what was typed is not that."""
    try:
        passkey = int(str(value).strip())
    except (TypeError, ValueError):
        return None
    return passkey if 0 <= passkey <= PASSKEY_MAX else None


def answer(connection, message):
    request_id = message.get("id")
    if request_id not in State.pending:
        # Already withdrawn -- BlueZ gave up, or the device went away while the
        # prompt was still on screen and an answer was on its way.
        return

    invocation = State.pending.pop(request_id)
    kind = State.kinds.pop(request_id, "")
    path = State.devices.pop(request_id, "")
    if State.displays.get(path) == request_id:
        del State.displays[path]

    if invocation is None:
        return

    if not message.get("accept"):
        invocation.return_dbus_error(REJECTED, "The request was refused")
        return

    if kind == "pin":
        invocation.return_value(GLib.Variant("(s)", (str(message.get("value", "")),)))
    elif kind == "passkey":
        passkey = passkey_from(message.get("value"))
        if passkey is None:
            invocation.return_dbus_error(REJECTED, "That is not a passkey")
            return
        invocation.return_value(GLib.Variant("(u)", (passkey,)))
    else:
        invocation.return_value(None)

    # Not for "service": allowing one profile once is not the same as vouching
    # for the device, and that request only ever reaches an already-paired one.
    if kind in ("confirm", "authorize", "passkey", "pin"):
        trust(connection, path)


def on_method_call(connection, sender, object_path, interface_name, method_name, parameters, invocation):
    if method_name == "Release":
        drop_all("released")
        invocation.return_value(None)
        return

    if method_name == "Cancel":
        drop_all("canceled")
        invocation.return_value(None)
        return

    if method_name == "RequestPinCode":
        ask(connection, "pin", parameters.unpack()[0], invocation)
        return

    if method_name == "RequestPasskey":
        ask(connection, "passkey", parameters.unpack()[0], invocation)
        return

    if method_name == "RequestConfirmation":
        path, passkey = parameters.unpack()
        ask(connection, "confirm", path, invocation, passkey=f"{passkey:06d}")
        return

    if method_name == "RequestAuthorization":
        ask(connection, "authorize", parameters.unpack()[0], invocation)
        return

    if method_name == "AuthorizeService":
        path, uuid = parameters.unpack()
        # A device the person has already vouched for is not asked about again:
        # that is what trusting one is for, and a headset reconnecting asks for
        # its profiles every single time.
        if device_properties(connection, path).get("Trusted"):
            invocation.return_value(None)
            return
        ask(connection, "service", path, invocation, uuid=uuid, service=service_name(uuid))
        return

    if method_name == "DisplayPasskey":
        path, passkey, entered = parameters.unpack()
        show(connection, "displayPasskey", path, passkey=f"{passkey:06d}", entered=entered)
        invocation.return_value(None)
        return

    if method_name == "DisplayPinCode":
        path, pincode = parameters.unpack()
        show(connection, "displayPin", path, pincode=pincode)
        invocation.return_value(None)
        return

    invocation.return_dbus_error(
        "org.freedesktop.DBus.Error.UnknownMethod", f"No such method: {method_name}"
    )


def register(connection):
    try:
        connection.call_sync(
            BLUEZ, BLUEZ_ROOT, AGENT_MANAGER_IFACE, "RegisterAgent",
            GLib.Variant("(os)", (AGENT_PATH, CAPABILITY)), None,
            Gio.DBusCallFlags.NONE, 5000, None,
        )
    except GLib.Error as error:
        if "AlreadyExists" not in error.message:
            log(f"cannot register: {error.message}")
            emit({"event": "error", "message": error.message})
            return

    try:
        connection.call_sync(
            BLUEZ, BLUEZ_ROOT, AGENT_MANAGER_IFACE, "RequestDefaultAgent",
            GLib.Variant("(o)", (AGENT_PATH,)), None,
            Gio.DBusCallFlags.NONE, 5000, None,
        )
    except GLib.Error as error:
        # Not fatal. Another agent holds the default -- blueman, an open
        # bluetoothctl -- and BlueZ still comes here for pairings this session
        # starts itself, which is nearly all of them.
        log(f"not the default agent: {error.message}")

    log("registered")
    emit({"event": "ready"})


def unregister(connection):
    try:
        connection.call_sync(
            BLUEZ, BLUEZ_ROOT, AGENT_MANAGER_IFACE, "UnregisterAgent",
            GLib.Variant("(o)", (AGENT_PATH,)), None,
            Gio.DBusCallFlags.NONE, 2000, None,
        )
    except GLib.Error:
        # Going away is what unregisters an agent; this is only the tidy way.
        pass


def read_line(stream, result, connection):
    try:
        line, _length = stream.read_line_finish_utf8(result)
    except GLib.Error as error:
        log(f"cannot read stdin: {error.message}")
        State.loop.quit()
        return

    if line is None:
        # The shell is gone, and an agent outliving it would answer for a shell
        # that cannot ask anybody anything.
        State.loop.quit()
        return

    line = line.strip()
    if line:
        try:
            answer(connection, json.loads(line))
        except ValueError as error:
            log(f"cannot read an answer: {error}")

    stream.read_line_async(GLib.PRIORITY_DEFAULT, None, read_line, connection)


def main():
    try:
        connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    except GLib.Error as error:
        log(f"no system bus: {error.message}")
        return 1

    State.connection = connection
    State.loop = GLib.MainLoop()

    interface = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML).interfaces[0]
    try:
        connection.register_object_with_closures2(AGENT_PATH, interface, on_method_call, None, None)
    except GLib.Error as error:
        log(f"cannot export {AGENT_PATH}: {error.message}")
        return 1

    # Registration is tied to bluetoothd being up rather than done once at
    # start: the daemon forgets every agent when it restarts, and it restarts
    # whenever the adapter is reset.
    Gio.bus_watch_name_on_connection(
        connection, BLUEZ, Gio.BusNameWatcherFlags.NONE,
        lambda conn, name, owner: register(conn),
        lambda conn, name: drop_all("gone"),
    )

    stdin = Gio.DataInputStream(base_stream=unix_input_stream(0, False))
    stdin.read_line_async(GLib.PRIORITY_DEFAULT, None, read_line, connection)

    unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, State.loop.quit)
    unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, State.loop.quit)

    State.loop.run()
    unregister(connection)
    return 0


if __name__ == "__main__":
    sys.exit(main())
