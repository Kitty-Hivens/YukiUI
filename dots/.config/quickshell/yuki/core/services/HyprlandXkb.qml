pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    /** The variant of each layout, "" where there is none. */
    property list<string> layoutVariants: []
    /**
     * Which of the layouts is active, as the keyboard reports it, or -1 until
     * it has.
     *
     * Matching the active layout's name back to a code is not enough to find
     * it in the list: a variant comes back as "ru:phonetic" while the list
     * holds "ru", and two variants of one layout share a code.
     */
    property int currentLayoutIndex: -1
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool needsLayoutRefresh: false

    // Update the layout code according to the layout name (Hyprland gives the name not the code)
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                const foundLine = lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }
                    
                    return false;
                });
                // console.log("[HyprlandXkb] Found line:", foundLine);
                // console.log("[HyprlandXkb] Layout:", root.currentLayoutName, "| Code:", root.currentLayoutCode);
                // console.log("[HyprlandXkb] Cached layout codes:", JSON.stringify(root.cachedLayoutCodes, null, 2));
            }
        }
    }

    // Find out available layouts and current active layout. Should only be necessary on init
    Process {
        id: fetchLayoutsProc
        running: true
        command: ["hyprctl", "-j", "devices"]

        // A switch reported while a read is under way is read again after it,
        // so a quick second switch is not lost.
        property bool again: false
        onRunningChanged: {
            if (!fetchLayoutsProc.running && fetchLayoutsProc.again) {
                fetchLayoutsProc.again = false;
                fetchLayoutsProc.running = true;
            }
        }

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                const parsedOutput = JSON.parse(devicesCollector.text);
                const hyprlandKeyboard = parsedOutput["keyboards"].find(kb => kb.main === true);
                root.layoutCodes = hyprlandKeyboard["layout"].split(",");
                const variants = (hyprlandKeyboard["variant"] ?? "").split(",");
                root.layoutVariants = root.layoutCodes.map((code, index) => variants[index] ?? "");
                root.currentLayoutIndex = hyprlandKeyboard["active_layout_index"] ?? -1;
                root.currentLayoutName = hyprlandKeyboard["active_keymap"];
                // console.log("[HyprlandXkb] Fetched | Layouts (multiple: " + (root.layoutCodes.length > 1) + "): "
                //     + root.layoutCodes.join(", ") + " | Active: " + root.currentLayoutName);
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                // With one layout known, an event means the list itself may
                // have changed, as it does when a second layout is set live.
                if (root.needsLayoutRefresh || root.layoutCodes.length <= 1) {
                    root.needsLayoutRefresh = false;
                    fetchLayoutsProc.running = true;
                }

                // If there's only one layout, the updated layout is always the same
                if (root.layoutCodes.length <= 1) return;

                // The event names the layout but not its place in the list.
                if (fetchLayoutsProc.running)
                    fetchLayoutsProc.again = true;
                else
                    fetchLayoutsProc.running = true;

                // Update when layout might have changed
                const dataString = event.data;
                root.currentLayoutName = dataString.substring(dataString.indexOf(",") + 1);

                // Update layout for on-screen keyboard (osk)
                Config.options.osk.layout = root.currentLayoutName.split(" (")[0];
            } else if (event.name == "configreloaded") {
                // Read now: a reload that changes the layouts need not be
                // followed by a layout switch to report it.
                root.needsLayoutRefresh = false;
                fetchLayoutsProc.running = true;
            }
        }
    }
}
