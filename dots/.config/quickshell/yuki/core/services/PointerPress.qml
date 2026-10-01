pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Where each mouse press lands, heard without taking it.
 *
 * A panel closed by a click outside it has only a focus grab to hear that
 * click by, and Hyprland ends a grab by eating the click: the window clicked
 * gets neither the click nor, often, the focus. The press-report plugin posts
 * every press on the event socket instead, with what lies under the pointer,
 * and lets it through. A panel listens here while it is open and falls back to
 * a grab when the plugin is not loaded.
 */
Singleton {
    id: root

    /** The plugin is loaded, so presses are reported. */
    property bool available: false

    /**
     * A press. `kind` is "layer" with the layer's namespace as `name`, a popup
     * counting as the layer it belongs to, "window" with its address, or
     * "none".
     */
    signal pressed(string kind, string name)

    function check() {
        probe.running = true;
    }

    Process {
        id: probe
        command: ["hyprctl", "plugin", "list", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.available = JSON.parse(text).some(plugin => plugin.name === "press-report");
                } catch (error) {
                    root.available = false;
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "pointerpress") {
                // A report is proof the plugin is there, however it came to be
                // loaded, by hand or after this last looked.
                root.available = true;
                const at = event.data.indexOf(",");
                root.pressed(at < 0 ? event.data : event.data.slice(0, at), at < 0 ? "" : event.data.slice(at + 1));
            } else if (event.name === "configreloaded") {
                // Plugins are loaded from the config, so a reload can bring
                // this one in or take it away.
                root.check();
            }
        }
    }

    Component.onCompleted: root.check()
}
