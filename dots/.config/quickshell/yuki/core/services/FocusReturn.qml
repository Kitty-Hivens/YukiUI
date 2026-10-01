pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import qs.common
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

    /**
     * Makes a panel that holds the keyboard safe to let go of it.
     *
     * When a panel stops taking keys, Hyprland hands focus back to the window
     * that had it last. With the pointer over a surface that takes no keys, the
     * dock or the panel still on its way out, it does so without asking whether
     * that window is on a workspace anyone can see, and focusing a window brings
     * its workspace back: switch workspace while the launcher is open, close it,
     * and the screen jumps back to where the launcher was opened. With the
     * pointer anywhere else the keyboard is left with a window nobody can see.
     *
     * So when that window is out of sight, focus is let go of before the panel
     * lets go (this needs the minimize plugin), and handed afterwards to the
     * window last used on the workspace on screen. Returns whether it acted, so
     * the panel knows to give the compositor a moment before it lets go, and to
     * call handOver once it has.
     */
    property string handOverTo: ""

    function beforeLettingGo(): bool {
        const last = HyprlandData.windowList.find(win => win.focusHistoryID === 0);
        // A special workspace is left alone: whether it is showing is not
        // something the monitors report as it changes. One holding minimised
        // windows is never meant to show, and its window keeps the head of the
        // focus history after focus was let go of, so Hyprland would focus it
        // and bring the hidden workspace up over the screen.
        const parked = Minimize.originOf(last) > 0;
        if (!last || (last.workspace.id < 0 && !parked))
            return false;
        if (Hyprland.monitors.values.some(monitor => monitor.activeWorkspace?.id === last.workspace.id))
            return false;
        const onScreen = Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1;
        const next = HyprlandData.windowList
            .filter(win => win.workspace.id === onScreen && win.focusHistoryID >= 0)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0] ?? null;
        root.handOverTo = next?.address ?? "";
        Quickshell.execDetached(["hyprctl", "eval", "if hl.plugin.minimize and hl.plugin.minimize.reset_focus then hl.plugin.minimize.reset_focus() end"]);
        return true;
    }

    function handOver() {
        if (root.handOverTo.length > 0)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.handOverTo}" })`);
        root.handOverTo = "";
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
