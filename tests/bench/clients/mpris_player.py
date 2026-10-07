"""A media player for the bench, as far as MPRIS goes and no further.

    mpris_player.py NAME TITLE ARTIST [--seekable] [--untimed]

Owns org.mpris.MediaPlayer2.NAME on the session bus it is started on, plays a
track five minutes long that starts a minute in, and does what it is told:
play, pause and the rest change the state it reports, and a change of track
counts up. It plays nothing. Each command it carries out is printed, so a test
can see what reached it, a move through the track with where to, in seconds.

With --seekable it can be moved through. With --untimed it does not say how
long the track is, as a player that has not started one yet does not.
"""

import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402

NAME, TITLE, ARTIST = sys.argv[1:4]
SEEKABLE = "--seekable" in sys.argv[4:]
UNTIMED = "--untimed" in sys.argv[4:]
PATH = "/org/mpris/MediaPlayer2"

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg type="x" direction="in"/></method>
    <method name="SetPosition"><arg type="o" direction="in"/><arg type="x" direction="in"/></method>
    <signal name="Seeked"><arg type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

state = {"status": "Playing", "track": 1, "position": 60_000_000}


def metadata():
    fields = {
        "mpris:trackid": GLib.Variant("o", f"/bench/track/{state['track']}"),
        "xesam:title": GLib.Variant("s", TITLE if state["track"] == 1 else f"{TITLE} {state['track']}"),
        "xesam:artist": GLib.Variant("as", [ARTIST]),
    }
    if not UNTIMED:
        fields["mpris:length"] = GLib.Variant("x", 300_000_000)
    return GLib.Variant("a{sv}", fields)


def get_property(_connection, _sender, _path, interface, name):
    values = {
        "Identity": GLib.Variant("s", NAME),
        "DesktopEntry": GLib.Variant("s", ""),
        "CanQuit": GLib.Variant("b", False),
        "CanRaise": GLib.Variant("b", False),
        "HasTrackList": GLib.Variant("b", False),
        "SupportedUriSchemes": GLib.Variant("as", []),
        "SupportedMimeTypes": GLib.Variant("as", []),
        "PlaybackStatus": GLib.Variant("s", state["status"]),
        "Metadata": metadata(),
        "Position": GLib.Variant("x", state["position"]),
        "Rate": GLib.Variant("d", 1.0),
        "Volume": GLib.Variant("d", 1.0),
        "CanGoNext": GLib.Variant("b", True),
        "CanGoPrevious": GLib.Variant("b", True),
        "CanPlay": GLib.Variant("b", True),
        "CanPause": GLib.Variant("b", True),
        "CanSeek": GLib.Variant("b", SEEKABLE),
        "CanControl": GLib.Variant("b", True),
    }
    return values.get(name)


def changed(connection, names):
    values = {name: get_property(None, None, None, None, name) for name in names}
    connection.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                           GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", values, [])))


def method_call(connection, _sender, _path, _interface, method, _parameters, invocation):
    if method in ("Play", "Pause", "PlayPause", "Stop"):
        state["status"] = {"Play": "Playing", "Pause": "Paused", "Stop": "Stopped"}.get(
            method, "Paused" if state["status"] == "Playing" else "Playing")
        changed(connection, ["PlaybackStatus"])
    elif method in ("Next", "Previous"):
        state["track"] = max(1, state["track"] + (1 if method == "Next" else -1))
        changed(connection, ["Metadata"])
    elif method == "SetPosition" and SEEKABLE:
        _track, position = _parameters.unpack()
        state["position"] = position
        connection.emit_signal(None, PATH, "org.mpris.MediaPlayer2.Player", "Seeked", GLib.Variant("(x)", (position,)))
        print(method, position // 1_000_000, flush=True)
        invocation.return_value(None)
        return
    print(method, flush=True)
    invocation.return_value(None)


def on_bus(connection, _name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    for interface in node.interfaces:
        connection.register_object(PATH, interface, method_call, get_property, None)


def on_name(_connection, _name):
    print("ready", flush=True)


Gio.bus_own_name(Gio.BusType.SESSION, f"org.mpris.MediaPlayer2.{NAME}", Gio.BusNameOwnerFlags.NONE, on_bus, on_name, None)
GLib.MainLoop().run()
