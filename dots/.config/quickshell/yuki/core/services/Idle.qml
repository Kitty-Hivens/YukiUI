pragma Singleton
import qs.core
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Keeps the machine awake while something asks it to.
 *
 * The inhibitor only counts while its surface is mapped, so it hangs off a loader
 * driven by the flag rather than being made once. The compositor closes that
 * surface when its monitor goes away, which is what the respawn below is for.
 */
Singleton {
    id: root

    property bool inhibit: false
    property bool respawning: false

    function load() {}

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    IpcHandler {
        target: "idle"

        function status(): string {
            return root.inhibit ? "inhibiting" : "off";
        }
        function toggle(): void {
            root.toggleInhibit();
        }
        function enable(): void {
            root.toggleInhibit(true);
        }
        function disable(): void {
            root.toggleInhibit(false);
        }
    }

    function syncFromPersistent() {
        if (!Persistent.ready) return;
        if (!Persistent.isNewHyprlandInstance) {
            root.inhibit = Persistent.states.idle.inhibit;
        } else {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    Component.onCompleted: root.syncFromPersistent()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.syncFromPersistent();
        }
    }

    // The compositor closes the inhibitor surface when its monitor goes away; recreate on screen changes.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.inhibit) respawnTimer.restart();
        }
    }

    Timer {
        id: respawnTimer
        interval: 1000
        onTriggered: {
            if (!root.inhibit || Quickshell.screens.length === 0) return;
            root.respawning = true;
            Qt.callLater(() => root.respawning = false);
        }
    }

    // Hyprland 0.56 does not count an inhibitor on a layer surface, and the one
    // below is on a layer, so on its own it held nothing off. The same request
    // also goes to logind, which hypridle honours. Only idling is blocked, so a
    // suspend asked for by hand still happens. The inhibitor lives as long as
    // cat reads from the shell, so it cannot outlive the shell.
    Process {
        running: root.inhibit
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=idle", "--who=Yuki", "--why=Keep awake is on", "--mode=block", "cat"]
    }

    LazyLoader {
        active: root.inhibit && !root.respawning
        component: IdleInhibitor {
            enabled: true
            window: PanelWindow {
                // Inhibitor only counts while its surface is mapped and visible.
                WlrLayershell.namespace: "quickshell:idleInhibitor"
                // Under the windows. A layer above a fullscreen game, even one
                // pixel of it, keeps the game from being shown on its own.
                WlrLayershell.layer: WlrLayer.Background
                implicitWidth: 0
                implicitHeight: 0
                color: "transparent"
                anchors {
                    right: true
                    bottom: true
                }
                // Make it not interactable
                mask: Region {
                    item: null
                }
            }
        }
    }
}
