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
     */
    signal blocklistChanged(bool excluded)

    function setExcluded(node, excluded) {
        const nodeName = node?.properties?.["node.name"] ?? "";
        if (nodeName.length === 0)
            return false;
        blocklistProc.excluded = excluded;
        blocklistProc.command = ["sh", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/audio/ee_blocklist.sh")),
            excluded ? "add" : "remove", nodeName, node.isSink ? "output" : "input"];
        blocklistProc.running = true;
        return true;
    }

    Process {
        id: blocklistProc
        property bool excluded: false
        onExited: exitCode => {
            if (exitCode === 0)
                root.blocklistChanged(blocklistProc.excluded);
            else
                console.log("[EasyEffects] could not change the exclusion list, exit", exitCode);
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
