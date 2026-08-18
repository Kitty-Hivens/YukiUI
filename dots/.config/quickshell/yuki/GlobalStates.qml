import qs.core
import qs.core.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenSharePickerOpen: false
    property bool screenShareRegionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool oskOpen: false
    property var oskWindow: null

    /**
     * Raised by something drawn inside a panel that does not know which panel.
     *
     * A quick toggle and a notification both close the surface they were opened
     * from, and both are written once for every environment. Naming the panel
     * here put the name of one environment's surface into the shared code; the
     * environment that has a panel up answers this instead.
     */
    signal panelDismissRequested()

    onScreenLockedChanged: {
        Persistent.states.lock.locked = root.screenLocked;
    }

    // Relock after a reload of the same instance; a fresh boot keeps no old lock.
    function restoreLockState() {
        if (!Persistent.ready) return;
        if (!Persistent.isNewHyprlandInstance && Persistent.states.lock.locked) {
            root.screenLocked = true;
        }
    }

    Component.onCompleted: root.restoreLockState()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreLockState();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}