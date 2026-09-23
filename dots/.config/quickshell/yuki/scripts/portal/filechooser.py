"""Backend for org.freedesktop.impl.portal.FileChooser.

xdg-desktop-portal-gnome grew a hard dependency on org.gnome.Mutter.ServiceChannel
for its file dialog, a private Wayland channel only Mutter hands out, so under a
wlroots session the GNOME chooser fails to start and every "open"/"save" dialog
dies with it. This answers the interface itself and shows a Quickshell dialog of
the yuki family's own, so the picker matches the rest of the desktop.

The dialog lives inside the running shell, not in a process of its own, so it wears
the family's own widgets and the live wallpaper palette rather than a copy that would
drift. It is opened over Quickshell IPC exactly the way the screen share picker is
(see scripts/screenShare/picker.sh): the call opens the panel and returns at once,
then the choice comes back through a fifo, read on a helper process this backend
waits on so the D-Bus main loop keeps turning. The shell shows one dialog at a time
(a newer request supersedes an in-flight one), though this backend can track several.
"""

import functools
import json
import os
import tempfile

import gi

gi.require_version("Gio", "2.0")

from gi.repository import Gio, GLib  # noqa: E402  (must follow require_version)

from common import OBJECT_PATH, RESPONSE_CANCELLED, RESPONSE_FAILED, RESPONSE_SUCCESS, make_log

log = make_log("filechooser")

# The shell runs as a Quickshell config named after its directory, and the dialog
# lives inside it. Resolve the name from this file's location, two levels below the
# config root, rather than hard-coding it, so a renamed config still resolves -- the
# same reasoning as scripts/screenShare/picker.sh.
CONFIG_NAME = os.path.basename(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
IPC_TARGET = "filePicker"

MODE_BY_METHOD = {"OpenFile": "open", "SaveFile": "save", "SaveFiles": "savefiles"}

# glob patterns carry a filter type of 0, mime types 1, in the a(sa(us)) each
# filter is built from.
FILTER_GLOB = 0
FILTER_MIME = 1

INTROSPECTION_XML = """
<node>
  <interface name='org.freedesktop.impl.portal.FileChooser'>
    <method name='OpenFile'>
      <arg type='o' name='handle' direction='in'/>
      <arg type='s' name='app_id' direction='in'/>
      <arg type='s' name='parent_window' direction='in'/>
      <arg type='s' name='title' direction='in'/>
      <arg type='a{sv}' name='options' direction='in'/>
      <arg type='u' name='response' direction='out'/>
      <arg type='a{sv}' name='results' direction='out'/>
    </method>
    <method name='SaveFile'>
      <arg type='o' name='handle' direction='in'/>
      <arg type='s' name='app_id' direction='in'/>
      <arg type='s' name='parent_window' direction='in'/>
      <arg type='s' name='title' direction='in'/>
      <arg type='a{sv}' name='options' direction='in'/>
      <arg type='u' name='response' direction='out'/>
      <arg type='a{sv}' name='results' direction='out'/>
    </method>
    <method name='SaveFiles'>
      <arg type='o' name='handle' direction='in'/>
      <arg type='s' name='app_id' direction='in'/>
      <arg type='s' name='parent_window' direction='in'/>
      <arg type='s' name='title' direction='in'/>
      <arg type='a{sv}' name='options' direction='in'/>
      <arg type='u' name='response' direction='out'/>
      <arg type='a{sv}' name='results' direction='out'/>
    </method>
    <property name='version' type='u' access='read'/>
  </interface>
</node>
"""


def _decode_path(value):
    """A portal path option is a nul-terminated byte array (D-Bus `ay`).

    PyGObject unpacks `ay` as `bytes` in some versions and as a list of ints in
    others, so both are handled; anything else is a last-resort string. Getting the
    list case wrong is what put "[47, 104, 111, ...]" (the char codes) into the path.
    """
    if value is None:
        return ""
    if isinstance(value, (bytes, bytearray)):
        return os.fsdecode(bytes(value).rstrip(b"\x00"))
    if isinstance(value, (list, tuple)):
        try:
            return os.fsdecode(bytes(value).rstrip(b"\x00"))
        except (ValueError, TypeError):
            return ""
    return str(value)


def _parse_filters(raw):
    """Flatten a(sa(us)) into what the picker reads: a name and its glob patterns.
    Mime rules are carried along untouched -- the picker does not match on them
    yet, but dropping them here would lose the filter's real intent."""
    filters = []
    for entry in raw or []:
        name, rules = entry
        filters.append({
            "name": name,
            "patterns": [pattern for (kind, pattern) in rules if kind == FILTER_GLOB],
            "mimes": [pattern for (kind, pattern) in rules if kind == FILTER_MIME],
        })
    return filters


def _build_request(method_name, title, options):
    mode = MODE_BY_METHOD[method_name]
    request = {
        "mode": mode,
        "title": title,
        "acceptLabel": options.get("accept_label", ""),
        "multiple": bool(options.get("multiple", False)) and mode == "open",
        # A batch save has no file list of its own to draw, so it picks the folder
        # the files land in, the same shape as a directory open.
        "directory": bool(options.get("directory", False)) or mode == "savefiles",
        "currentFolder": _decode_path(options.get("current_folder")),
        "filters": _parse_filters(options.get("filters")),
    }
    if mode == "save":
        request["saveName"] = options.get("current_name", "")
        current_file = _decode_path(options.get("current_file"))
        if current_file:
            if not request["currentFolder"]:
                request["currentFolder"] = os.path.dirname(current_file)
            if not request["saveName"]:
                request["saveName"] = os.path.basename(current_file)
    return request


def _cleanup_fifo(tmpdir, fifo):
    try:
        os.unlink(fifo)
    except OSError:
        pass
    try:
        os.rmdir(tmpdir)
    except OSError:
        pass


def _spawn_picker(request, on_done):
    """Open the dialog in the running shell and read the choice from a fifo.

    Mirrors scripts/screenShare/picker.sh: the ipc call opens the panel and returns
    at once, then `cat` blocks on the fifo until the shell writes the answer, with a
    timeout so a dead or wedged shell cannot hang the caller for ever. Waiting on that
    helper (rather than reading the fifo here) keeps the D-Bus main loop turning."""
    tmpdir = None
    try:
        tmpdir = tempfile.mkdtemp(prefix="yuki-picker-")
        fifo = os.path.join(tmpdir, "result")
        os.mkfifo(fifo)
    except OSError as error:
        log(f"cannot make the result fifo: {error}")
        if tmpdir is not None:
            try:
                os.rmdir(tmpdir)
            except OSError:
                pass
        on_done(RESPONSE_FAILED, None)
        return

    script = (
        'qs -c "$1" ipc call "$2" open "$3" "$4" >/dev/null 2>&1 || exit 0\n'
        'timeout 300 cat "$4"\n'
    )
    argv = ["sh", "-c", script, "yuki-picker", CONFIG_NAME, IPC_TARGET, json.dumps(request), fifo]
    launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.STDOUT_PIPE)
    try:
        process = launcher.spawnv(argv)
    except GLib.Error as error:
        log(f"cannot reach the shell: {error.message}")
        _cleanup_fifo(tmpdir, fifo)
        on_done(RESPONSE_FAILED, None)
        return

    process.communicate_utf8_async(None, None, functools.partial(_on_picker_done, on_done, tmpdir, fifo))


def _on_picker_done(on_done, tmpdir, fifo, process, result):
    stdout = ""
    try:
        _ok, stdout, _stderr = process.communicate_utf8_finish(result)
    except GLib.Error as error:
        log(f"reading the shell reply failed: {error.message}")
    _cleanup_fifo(tmpdir, fifo)
    text = (stdout or "").strip()
    if not text:
        on_done(RESPONSE_CANCELLED, None)
        return
    try:
        payload = json.loads(text)
    except ValueError:
        log("shell reply was not valid json")
        on_done(RESPONSE_CANCELLED, None)
        return
    if not isinstance(payload, dict):
        log("shell reply was not a json object")
        on_done(RESPONSE_FAILED, None)
        return
    on_done(payload.get("response", RESPONSE_CANCELLED), payload.get("uris"))


def _expand_savefiles(folder_uris, options):
    """SaveFiles hands the app back a full uri per proposed name, so the folder the
    dialog returned is joined with each name the caller asked to write."""
    folder = Gio.File.new_for_uri(folder_uris[0]).get_path()
    if folder is None:
        return []
    uris = []
    for name in options.get("files") or []:
        # Force a basename: a proposed name that is absolute or has ".." must not
        # escape the folder the user actually chose.
        decoded = os.path.basename(_decode_path(name))
        if decoded:
            uris.append(Gio.File.new_for_path(os.path.join(folder, decoded)).get_uri())
    return uris


def _return(invocation, response, uris):
    results = {}
    if uris:
        results["uris"] = GLib.Variant("as", uris)
    invocation.return_value(GLib.Variant("(ua{sv})", (response, results)))


def _finish(invocation, method_name, options, response, uris):
    # Whatever happens here, the caller must get exactly one reply: a hung D-Bus call
    # is worse than a failed one and would defeat the fifo read timeout.
    try:
        if response == RESPONSE_SUCCESS and isinstance(uris, list) and uris:
            if method_name == "SaveFiles":
                uris = _expand_savefiles(uris, options)
            _return(invocation, RESPONSE_SUCCESS, uris)
        elif response == RESPONSE_CANCELLED:
            _return(invocation, RESPONSE_CANCELLED, None)
        else:
            _return(invocation, RESPONSE_FAILED, None)
    except Exception as error:  # last-resort guard so the reply always goes out
        log(f"failed to return the pick: {error}")
        try:
            _return(invocation, RESPONSE_FAILED, None)
        except Exception:
            pass


def on_method_call(connection, sender, object_path, interface_name, method_name, parameters, invocation):
    if method_name not in MODE_BY_METHOD:
        invocation.return_dbus_error(
            "org.freedesktop.DBus.Error.UnknownMethod", f"No such method: {method_name}"
        )
        return
    # The request `handle` (o) is where a fuller impl would export an
    # org.freedesktop.impl.portal.Request with Close(), so xdg-desktop-portal could
    # dismiss the dialog if the app exits. Not implemented; the shell-side session
    # timeout bounds an orphaned dialog instead.
    _handle, app_id, _parent_window, title, options = parameters.unpack()
    log(f"{method_name} from {app_id or 'an unsandboxed app'}: {title!r}")
    request = _build_request(method_name, title, options)
    _spawn_picker(request, functools.partial(_finish, invocation, method_name, options))


def on_get_property(connection, sender, object_path, interface_name, property_name):
    if property_name == "version":
        return GLib.Variant("u", 3)
    return None


def register(connection):
    interface = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML).interfaces[0]
    connection.register_object_with_closures2(
        OBJECT_PATH, interface, on_method_call, on_get_property, None
    )
