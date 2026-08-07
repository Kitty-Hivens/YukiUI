#!/usr/bin/env python3
"""Backend for org.freedesktop.impl.portal.Wallpaper.

Nothing in a wlroots session implements this interface, so "Set as Background" in
Nautilus -- and every other libportal caller -- reaches xdg-desktop-portal and
stops there. This hands the picture to switchwall.sh instead, the same entry point
the shell's own wallpaper selector uses, so the generated palette follows the
wallpaper the way it does everywhere else.
"""

import os
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402  (must follow require_version)

BUS_NAME = "org.freedesktop.impl.portal.desktop.yuki"
OBJECT_PATH = "/org/freedesktop/portal/desktop"

DOCUMENTS_NAME = "org.freedesktop.portal.Documents"
DOCUMENTS_PATH = "/org/freedesktop/portal/documents"

# Response codes of org.freedesktop.impl.portal.Request. 1, "cancelled", never comes
# up here: there is no dialog to cancel.
RESPONSE_SUCCESS = 0
RESPONSE_FAILED = 2

SWITCHWALL = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "colors", "switchwall.sh")
)

INTROSPECTION_XML = """
<node>
  <interface name='org.freedesktop.impl.portal.Wallpaper'>
    <method name='SetWallpaperURI'>
      <arg type='o' name='handle' direction='in'/>
      <arg type='s' name='app_id' direction='in'/>
      <arg type='s' name='parent_window' direction='in'/>
      <arg type='s' name='uri' direction='in'/>
      <arg type='a{sv}' name='options' direction='in'/>
      <arg type='u' name='response' direction='out'/>
    </method>
    <property name='version' type='u' access='read'/>
  </interface>
</node>
"""


def log(message):
    print(f"[wallpaper-portal] {message}", file=sys.stderr, flush=True)


def undo_document_store(connection, path):
    """Trade a document store path for the file it stands for.

    The document store is a FUSE view that lives only as long as the exporting app
    keeps its handle, while switchwall.sh records the path in the shell config to
    put the wallpaper back on the next login -- so a path from there would come
    back dead.
    """
    try:
        mount_point = connection.call_sync(
            DOCUMENTS_NAME, DOCUMENTS_PATH, DOCUMENTS_NAME,
            "GetMountPoint", None, GLib.VariantType("(ay)"),
            Gio.DBusCallFlags.NONE, 5000, None,
        ).get_child_value(0).get_bytestring()
    except GLib.Error as error:
        log(f"document store unavailable: {error.message}")
        return path

    prefix = os.path.join(os.fsdecode(mount_point), "")
    if not path.startswith(prefix):
        return path

    doc_id = path[len(prefix):].split(os.sep)[0]
    try:
        original = connection.call_sync(
            DOCUMENTS_NAME, DOCUMENTS_PATH, DOCUMENTS_NAME,
            "Info", GLib.Variant("(s)", (doc_id,)), GLib.VariantType("(aya{sas})"),
            Gio.DBusCallFlags.NONE, 5000, None,
        ).get_child_value(0).get_bytestring()
    except GLib.Error as error:
        log(f"cannot resolve document {doc_id}: {error.message}")
        return path

    return os.fsdecode(original)


def set_wallpaper(connection, uri):
    path = Gio.File.new_for_uri(uri).get_path()
    if path is None:
        log(f"not a local file: {uri}")
        return RESPONSE_FAILED

    path = undo_document_store(connection, path)
    if not os.path.isfile(path):
        log(f"no such file: {path}")
        return RESPONSE_FAILED

    log(f"switching wallpaper to {path}")
    try:
        # switchwall.sh regenerates the whole palette and may sit on a notification
        # prompt for half a minute, well past the caller's D-Bus timeout, so it is
        # let go of rather than waited for.
        subprocess.Popen(
            [SWITCHWALL, "--image", path],
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        log(f"cannot run {SWITCHWALL}: {error}")
        return RESPONSE_FAILED

    return RESPONSE_SUCCESS


def on_method_call(connection, sender, object_path, interface_name, method_name, parameters, invocation):
    if method_name != "SetWallpaperURI":
        invocation.return_dbus_error(
            "org.freedesktop.DBus.Error.UnknownMethod", f"No such method: {method_name}"
        )
        return

    _handle, app_id, _parent_window, uri, _options = parameters.unpack()
    log(f"request from {app_id or 'an unsandboxed app'}: {uri}")
    # The set-on option is ignored: the lock screen draws the desktop wallpaper, so
    # background, lockscreen and both all come down to the same switch. show-preview
    # is ignored too -- picking a wallpaper applies it right away in this shell.
    invocation.return_value(GLib.Variant("(u)", (set_wallpaper(connection, uri),)))


def on_get_property(connection, sender, object_path, interface_name, property_name):
    if property_name == "version":
        return GLib.Variant("u", 1)
    return None


def main():
    if not os.access(SWITCHWALL, os.X_OK):
        log(f"{SWITCHWALL} is missing or not executable")
        return 1

    loop = GLib.MainLoop()
    interface = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML).interfaces[0]

    def on_bus_acquired(connection, name):
        try:
            connection.register_object_with_closures2(
                OBJECT_PATH, interface, on_method_call, on_get_property, None
            )
        except GLib.Error as error:
            log(f"cannot export {OBJECT_PATH}: {error.message}")
            loop.quit()

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
