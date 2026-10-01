import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core.services

// Keeps a maximised window in front once it is the active one.
//
// Hyprland maximises a window as a kind of fullscreen, and a window in that
// state is not raised by bring_to_top: brought up from the dock, by Alt+Tab or
// by a click on what showed of it, it took the focus and stayed under the
// floating windows that had been over it. Lowering those works, so that is
// what happens, whenever a maximised window becomes active: the floating
// windows of its workspace go under it, the most recently used first, which
// keeps their own order.
Scope {
    id: root

    property string pendingAddress: ""

    function check(address: string) {
        if (!/^0x[0-9a-f]+$/.test(address))
            return;
        root.pendingAddress = address;
        // Read fresh: the shared window list is behind by a read, and a
        // window maximised a moment ago would not show as such yet.
        if (!reader.running)
            reader.running = true;
        else
            reader.again = true;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "activewindowv2")
                root.check(`0x${event.data}`);
            else if (event.name === "fullscreen" && event.data === "1")
                root.check(HyprlandData.windowList.find(client => client.focusHistoryID === 0)?.address ?? "");
        }
    }

    Process {
        id: reader

        property bool again: false

        command: ["hyprctl", "clients", "-j"]
        onRunningChanged: {
            if (!reader.running && reader.again) {
                reader.again = false;
                reader.running = true;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let clients;
                try {
                    clients = JSON.parse(text);
                } catch (error) {
                    return;
                }
                const target = clients.find(client => client.address === root.pendingAddress);
                if (!target || target.fullscreen !== 1)
                    return;
                const over = clients.filter(client => client.address !== target.address
                    && client.workspace.id === target.workspace.id && client.floating && client.fullscreen === 0)
                    .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
                if (over.length === 0)
                    return;
                Quickshell.execDetached(["hyprctl", "eval", over.map(client =>
                    `hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = "address:${client.address}" }))`).join(" ")]);
            }
        }
    }
}
