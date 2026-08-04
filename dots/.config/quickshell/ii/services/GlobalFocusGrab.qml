pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    // Toplevel the grab took focus from, restored on dismiss. See refocusTimer.
    property string returnAddress: ""

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
        refocusTimer.restart();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            root.persistent.push(window);
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent.splice(index, 1);
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable.push(window);
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable.splice(index, 1);
        }
    }

    function hasActive(element) {
        return element?.activeFocus || Array.from(
            element?.children
        ).some(
            (child) => hasActive(child)
        );
    }

    HyprlandFocusGrab {
        id: grab
        windows: root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => hasActive(w?.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: root.dismissable.length > 0
        onActiveChanged: {
            if (!grab.active)
                return;
            const address = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
            root.returnAddress = address ? `0x${address}` : "";
        }
        onCleared: () => {
            root.dismiss();
        }
    }

    // With no_focus_fallback nothing takes focus once the grab lifts, so a fullscreen game
    // never re-arms its pointer lock and reads the dead input as a freeze. Skip the restore
    // when a panel handed focus to some other window -- that window earned it.
    Timer {
        id: refocusTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: {
            const address = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
            const focusVacated = !address || `0x${address}` === root.returnAddress;
            if (root.returnAddress && focusVacated) {
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.returnAddress}" })`);
            }
            root.returnAddress = "";
        }
    }
}
