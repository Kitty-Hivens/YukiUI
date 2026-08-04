import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Handles EasyEffects active state and presets.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false

    /**
     * Take one application out of processing, or put it back.
     *
     * EasyEffects grabs every stream, so a device chosen for one application
     * cannot hold until EasyEffects has been told to leave it alone. Its own
     * exclusion list does exactly that, and the list is read when a preset
     * loads -- both are handled by the script, which finishes before whatever
     * the caller wanted to do with the stream.
     *
     * Reported whether the list could be written or not: a caller waiting on
     * this before it moves a stream still has to move it when the answer is no.
     * Requests are answered in the order they were made.
     */
    signal blocklistSettled(bool ok)

    // One request at a time. The script rewrites a preset file and reloads it,
    // so two of them overlapping would race over the same file, and a caller
    // waiting on an answer has to hear about its own request rather than about
    // whichever one happened to finish first.
    property var blocklistQueue: []

    function setExcluded(node, excluded) {
        const nodeName = node?.properties?.["node.name"] ?? "";
        if (nodeName.length === 0)
            return false;
        root.blocklistQueue = root.blocklistQueue.concat([
            {
                name: nodeName,
                excluded: excluded,
                kind: node.isSink ? "output" : "input"
            }
        ]);
        root.runNextBlocklistRequest();
        return true;
    }

    function runNextBlocklistRequest() {
        if (blocklistProc.running || root.blocklistQueue.length === 0)
            return;
        const request = root.blocklistQueue[0];
        blocklistProc.command = ["sh", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/audio/ee_blocklist.sh")),
            request.excluded ? "add" : "remove", request.name, request.kind];
        blocklistProc.running = true;
    }

    Process {
        id: blocklistProc
        onExited: exitCode => {
            root.blocklistQueue = root.blocklistQueue.slice(1);
            if (exitCode !== 0)
                console.log("[EasyEffects] could not change the exclusion list, exit", exitCode);
            root.blocklistSettled(exitCode === 0);
            root.runNextBlocklistRequest();
        }
    }

    function fetchAvailability() {
        fetchAvailabilityProc.running = true
    }

    function fetchActiveState() {
        fetchActiveStateProc.running = true
    }

    function disable() {
        root.active = false
        Quickshell.execDetached(["bash", "-c", "pkill easyeffects || flatpak pkill com.github.wwmm.easyeffects"])
    }

    function enable() {
        root.active = true
        Quickshell.execDetached(["bash", "-c", "easyeffects --hide-window --service-mode || flatpak run com.github.wwmm.easyeffects --hide-window --service-mode"])
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v easyeffects || flatpak info com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
        }
    }

    Process {
        id: fetchActiveStateProc
        running: true
        command: ["bash", "-c", "pidof easyeffects || flatpak ps | grep com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
        }
    }
}
