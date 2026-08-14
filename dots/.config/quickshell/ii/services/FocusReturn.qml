pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Gives focus back to the window a panel took it from.
 *
 * With no_focus_fallback nothing takes focus once a panel closes. A fullscreen
 * game then never re-arms its pointer lock and reads the dead input as a
 * freeze, which is why this exists at all.
 *
 * Every panel that covers the screen has the same three moments: remember what
 * was focused, hand it back on the way out, or step aside because focus was
 * sent somewhere on purpose. Written per panel it drifted -- one copy checked
 * whether focus had actually been vacated and the other did not -- so it is
 * written once here and each panel names itself.
 */
Singleton {
    id: root

    /**
     * The window to go back to, and who is currently keeping it from getting
     * focus.
     *
     * Panels nest: a sidebar can open over the overview. The window worth
     * returning to is the one from before the first of them, so the address is
     * recorded once and held until the last of them is gone.
     */
    property string address: ""
    property var owners: []

    function remember(owner) {
        // A panel opening calls off a handback that has not happened yet: the
        // window it would have gone to is still the right one, and it is about
        // to be covered again.
        restoreTimer.stop();
        if (root.owners.indexOf(owner) === -1)
            root.owners = root.owners.concat([owner]);
        if (root.address.length > 0)
            return;
        const focused = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        root.address = focused ? `0x${focused}` : "";
    }

    /** Focus was directed somewhere on purpose: that window earned it. */
    function discard(owner) {
        root.owners = root.owners.filter(item => item !== owner);
        root.address = "";
    }

    function restore(owner) {
        root.owners = root.owners.filter(item => item !== owner);
        if (root.owners.length > 0 || root.address.length === 0)
            return;
        restoreTimer.restart();
    }

    // Waited out rather than done at once: the panel is still on its way off
    // screen, and asking for focus while it is up hands it straight back.
    Timer {
        id: restoreTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: {
            const focused = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
            // Nothing focused is the case this is for. The same window still
            // being named is worth a dispatch too: with no fallback focus it can
            // hold the title without holding the input, and asking again is what
            // re-arms a pointer lock.
            const vacated = !focused || `0x${focused}` === root.address;
            // Focusing a window also goes to the workspace it sits on. The
            // workspace the panel was opened over is not necessarily the one it
            // is closed over, and a window left behind there is not worth being
            // dragged back to. A window hyprland no longer lists is let through:
            // the dispatch finds nothing and does nothing.
            const target = Hyprland.toplevels.values.find(toplevel => `0x${toplevel.address}` === root.address);
            const onScreen = target?.workspace?.active ?? true;
            if (root.address.length > 0 && vacated && onScreen)
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.address}" })`);
            root.address = "";
        }
    }
}
