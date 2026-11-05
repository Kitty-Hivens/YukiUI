pragma Singleton

import qs.core
import qs.core.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    /** The checker is installed. Whether it runs by itself is the config's say. */
    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    /** What can be updated, as { name, from, to }. */
    property var packages: []
    /** The last check got no answer, so the figures are those of the one before. */
    property bool failed: false
    /** When a check last got an answer, or null. */
    property var lastChecked: null

    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    readonly property bool checksByItself: Config.ready && Config.options.updates.enableCheck
    onChecksByItselfChanged: {
        if (root.checksByItself)
            root.refresh();
    }

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    /**
     * What the checker said, with how it ended on the last line. It ends in 0
     * with updates, in 2 with none, and in anything else without having found
     * out, as it does with the network down. Counted through a pipe, that last
     * case read as nothing to update.
     */
    function take(text) {
        const lines = text.trim().split("\n");
        const status = parseInt((lines.pop() ?? "").replace("status ", ""));
        if (status !== 0 && status !== 2) {
            root.failed = true;
            return;
        }
        root.failed = false;
        root.lastChecked = new Date();
        root.packages = status === 2 ? [] : lines.map(line => {
            const parts = line.trim().split(/\s+/);
            return { name: parts[0] ?? "", from: parts[1] ?? "", to: parts[3] ?? "" };
        }).filter(entry => entry.name.length > 0);
        root.count = root.packages.length;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: root.checksByItself
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    // Looked for whether or not it checks by itself: a check by hand needs it too.
    Process {
        id: checkAvailabilityProc
        running: Config.ready
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            if (root.checksByItself)
                root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", "checkupdates; echo \"status $?\""]
        stdout: StdioCollector {
            onStreamFinished: root.take(text)
        }
    }
}
