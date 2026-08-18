pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import qs.core.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Reads them from `hyprctl binds` and groups them by the "Category: description" prefix.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    // The plain-text listing rather than `-j`: Hyprland 0.56 prints its bind JSON
    // with the keys and the values out of step, which no parser can rescue.
    function parseBinds(text: string): var {
        const binds = [];
        let bind = null;
        for (const line of text.split("\n")) {
            if (line.trim().length === 0) continue;
            if (!/^\s/.test(line)) { // A bind, binde, bindl... header starts a block
                bind = {
                    modmask: 0,
                    submap: "",
                    key: "",
                    keycode: 0,
                    catchall: false,
                    description: "",
                    dispatcher: "",
                    arg: ""
                };
                binds.push(bind);
                continue;
            }
            if (!bind) continue;
            const separator = line.indexOf(":");
            if (separator === -1) continue;
            const field = line.substring(0, separator).trim();
            const value = line.substring(separator + 1).trim(); // Descriptions carry their own colons
            if (field === "modmask" || field === "keycode") {
                bind[field] = parseInt(value) || 0;
            } else if (field === "catchall") {
                bind.catchall = (value === "true");
            } else if (field in bind) {
                bind[field] = value;
            }
        }
        return binds;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getKeybinds.running = true
            }
        }
    }

    Process {
        id: getKeybinds
        running: true
        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keybinds = root.parseBinds(text)
                    var groups = []
                    for (var i = 0; i < root.keybinds.length; i++) {
                        var bind = root.keybinds[i].description
                        var group = bind.substring(0, bind.indexOf(":"))
                        if (!groups.includes(group) && group.length > 0) {
                            groups.push(group)
                        }
                    }
                    root.keybindCategories = groups
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

