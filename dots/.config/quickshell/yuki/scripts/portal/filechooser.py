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

# How often the shell is asked whether it still holds a request, and how many
# answers in a row of "no" end it. Two, because the answer turns to "no" the
# moment the shell writes the choice, a little before the reader has it.
LIVENESS_SECONDS = 5
LIVENESS_MISSES = 2
# How long one question may take. A shell held up, by swap say, answers late
# or not at all, and that says nothing about the request. Shorter than the
# interval, so questions never pile up.
ASK_SECONDS = 3
# What _ask_shell hands on for a shell that did not answer in time.
NO_ANSWER = object()

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

REQUEST_XML = """
<node>
  <interface name='org.freedesktop.impl.portal.Request'>
    <method name='Close'/>
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


def _parse_filter(entry):
    """One (sa(us)) as the picker reads it: a name and its glob patterns. Mime
    rules are carried along untouched: the picker matches the common ones by
    extension, and dropping them here would lose the filter's real intent."""
    name, rules = entry
    return {
        "name": name,
        "patterns": [pattern for (kind, pattern) in rules if kind == FILTER_GLOB],
        "mimes": [pattern for (kind, pattern) in rules if kind == FILTER_MIME],
    }


def _same_filter(a, b):
    name_a, rules_a = a
    name_b, rules_b = b
    return name_a == name_b and [tuple(rule) for rule in rules_a] == [tuple(rule) for rule in rules_b]


def _offered_filters(options):
    """The filters the dialog offers, as the application sent them, and which
    of them it starts on. The application names that one in current_filter,
    which with no list of filters is the one filter to apply."""
    filters = [tuple(entry) for entry in options.get("filters") or []]
    current = options.get("current_filter")
    if current is None:
        return filters, 0
    current = tuple(current)
    if not filters:
        return [current], 0
    for index, entry in enumerate(filters):
        if _same_filter(entry, current):
            return filters, index
    return filters, 0


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
    }
    filters, current = _offered_filters(options)
    request["filters"] = [_parse_filter(entry) for entry in filters]
    request["currentFilter"] = current
    if mode == "savefiles":
        # The names the files will be written under, so the dialog can ask
        # about the ones already in the folder picked.
        request["files"] = [
            name for name in (os.path.basename(_decode_path(raw)) for raw in options.get("files") or []) if name
        ]
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


def _ask_shell(args, on_reply):
    """Calls the dialog's ipc target without blocking and hands on its stdout,
    None when the shell could not be reached, or NO_ANSWER when it was too slow."""
    argv = ["timeout", str(ASK_SECONDS), "qs", "-c", CONFIG_NAME, "ipc", "call", IPC_TARGET, *args]
    try:
        process = Gio.SubprocessLauncher.new(
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
        ).spawnv(argv)
    except GLib.Error:
        on_reply(None)
        return

    def done(process, result):
        try:
            ok, stdout, _stderr = process.communicate_utf8_finish(result)
        except GLib.Error:
            on_reply(None)
            return
        status = process.get_exit_status()
        if status == 124:
            on_reply(NO_ANSWER)
        else:
            on_reply(stdout.strip() if ok and status == 0 else None)

    process.communicate_utf8_async(None, None, done)


def _spawn_picker(request, on_done, connection=None, handle=None):
    """Open the dialog in the running shell and read the choice from a fifo.

    Mirrors scripts/screenShare/picker.sh: the ipc call opens the panel and returns
    at once, then `cat` blocks on the fifo until the shell writes the answer. Waiting
    on that helper (rather than reading the fifo here) keeps the D-Bus main loop
    turning.

    There is no time limit on the dialog. A flat one cancelled a dialog still being
    used. Instead the shell is asked every few seconds whether it still holds this
    request, and the reader is stopped once it does not, which covers a shell that
    died or restarted. The application can end the request itself through the
    Request object exported at `handle`."""
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
        'exec cat "$4"\n'
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

    state = {"done": False, "misses": 0, "watch": 0, "request_id": 0}

    def stop_reader():
        if not state["done"]:
            process.force_exit()

    def check():
        if state["done"]:
            return GLib.SOURCE_REMOVE

        def on_reply(reply):
            if state["done"] or reply is NO_ANSWER:
                return
            # A shell that could not be reached, gone say, or one that no
            # longer knows the request, restarted say, is a miss. One too
            # slow to answer was let go of above, as neither.
            missed = reply is None or reply == "false"
            state["misses"] = state["misses"] + 1 if missed else 0
            if state["misses"] >= LIVENESS_MISSES:
                log("the shell no longer holds the request, cancelling it")
                stop_reader()

        _ask_shell(["pending", fifo], on_reply)
        return GLib.SOURCE_CONTINUE

    state["watch"] = GLib.timeout_add_seconds(LIVENESS_SECONDS, check)

    if connection is not None and handle:
        def on_request_call(_conn, _sender, _path, _iface, method, _params, invocation):
            if method == "Close":
                _ask_shell(["closeRequest", fifo], lambda _reply: None)
                stop_reader()
            invocation.return_value(None)

        try:
            node = Gio.DBusNodeInfo.new_for_xml(REQUEST_XML).interfaces[0]
            state["request_id"] = connection.register_object_with_closures2(handle, node, on_request_call, None, None)
        except GLib.Error as error:
            log(f"cannot export the request object: {error.message}")

    def finished(process, result):
        state["done"] = True
        if state["watch"]:
            GLib.source_remove(state["watch"])
        if state["request_id"]:
            connection.unregister_object(state["request_id"])
        _on_picker_done(on_done, tmpdir, fifo, process, result)

    process.communicate_utf8_async(None, None, finished)


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
    on_done(payload.get("response", RESPONSE_CANCELLED), payload.get("uris"), payload.get("filter"))


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


def _results(uris, chosen_filter=None):
    results = {}
    if uris:
        results["uris"] = GLib.Variant("as", uris)
    if chosen_filter is not None:
        name, rules = chosen_filter
        results["current_filter"] = GLib.Variant("(sa(us))", (name, [tuple(rule) for rule in rules]))
    return results


def _return(invocation, response, uris, chosen_filter=None):
    invocation.return_value(GLib.Variant("(ua{sv})", (response, _results(uris, chosen_filter))))


def _chosen_filter(options, index):
    """The filter picked in the dialog, by its place in the list it was offered,
    for an application that saves in the format the filter names."""
    filters, _current = _offered_filters(options)
    if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(filters):
        return filters[index]
    return None


def _finish(invocation, method_name, options, response, uris, filter_index=None):
    # Whatever happens here, the caller must get exactly one reply: a hung D-Bus call
    # is worse than a failed one, and the application waits on it for good.
    try:
        if response == RESPONSE_SUCCESS and isinstance(uris, list) and uris:
            if method_name == "SaveFiles":
                uris = _expand_savefiles(uris, options)
            _return(invocation, RESPONSE_SUCCESS, uris, _chosen_filter(options, filter_index))
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
    # The request `handle` is where the Request object goes, whose Close() lets
    # xdg-desktop-portal take the dialog away when the application quits.
    handle, app_id, _parent_window, title, options = parameters.unpack()
    log(f"{method_name} from {app_id or 'an unsandboxed app'}: {title!r}")
    request = _build_request(method_name, title, options)
    _spawn_picker(request, functools.partial(_finish, invocation, method_name, options), connection, handle)


def on_get_property(connection, sender, object_path, interface_name, property_name):
    if property_name == "version":
        return GLib.Variant("u", 3)
    return None


def register(connection):
    interface = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML).interfaces[0]
    connection.register_object_with_closures2(
        OBJECT_PATH, interface, on_method_call, on_get_property, None
    )
