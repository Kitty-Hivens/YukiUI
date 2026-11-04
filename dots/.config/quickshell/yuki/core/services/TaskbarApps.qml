pragma Singleton

import qs.core
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Singleton {
    id: root

    // Compared without regard to case. The taskbar identifies an application by the
    // class its windows carry, lowercased, while the configuration holds whatever
    // spelling the application or the person editing it used -- so a pin written as
    // org.gnome.Nautilus was never recognised as the one behind org.gnome.nautilus.
    // It read as unpinned, pinning it again added the lowercase spelling beside the
    // original, and the next attempt removed only that addition: the entry could not
    // be unpinned at all.
    function isPinned(appId) {
        const wanted = (appId ?? "").toLowerCase();
        return Config.options.dock.pinnedApps.some(id => id.toLowerCase() === wanted);
    }

    function togglePin(appId) {
        const wanted = (appId ?? "").toLowerCase();
        if (root.isPinned(appId)) {
            // Every spelling of it, not just the one that was asked about.
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id.toLowerCase() !== wanted)
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    property list<var> apps: {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            // A pin to an application that is not installed cannot be started and
            // cannot be told apart from one that can, so it is left out of the view
            // rather than holding a place that does nothing. The configuration is not
            // touched: the pin comes back on its own once the application does.
            if (!AppSearch.entryFor(appId)) continue;
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                toplevels: []
            }));
        }
        const pinnedCount = map.size;

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        // One unusable pattern used to abandon this whole expression, leaving the
        // taskbar showing whatever it last managed to work out -- windows opening and
        // closing went unnoticed until the pattern was corrected, with nothing to say
        // why beyond a line in the log.
        const ignoredRegexes = [];
        for (const pattern of ignoredRegexStrings) {
            try {
                ignoredRegexes.push(new RegExp(pattern, "i"));
            } catch (error) {
                console.warn("[TaskbarApps] skipping an unusable ignore pattern:", pattern, "--", error.message);
            }
        }
        // Open windows
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            if (!map.has(toplevel.appId.toLowerCase())) map.set(toplevel.appId.toLowerCase(), ({
                toplevels: []
            }));
            map.get(toplevel.appId.toLowerCase()).toplevels.push(toplevel);
        }

        var values = [];
        var index = 0;

        for (const [key, value] of map) {
            // The separator divides the pinned entries from the rest, so it belongs
            // between them and only while both sides have something. Adding it as soon
            // as anything was pinned left it hanging off the end whenever every open
            // window belonged to an application that was pinned already.
            if (pinnedCount > 0 && index === pinnedCount) {
                values.push(root.separatorEntry);
            }
            values.push(root.heldEntry(key, value.toplevels));
            index++;
        }

        // Whatever is no longer on the taskbar lets go of the windows it was holding.
        for (const key of Object.keys(root.entryPool)) {
            if (!map.has(key)) root.entryPool[key].toplevels = [];
        }

        return values;
    }

    // One entry per application, kept across rebuilds. Handing out a new object each
    // time made every binding that reads an entry -- the icon guess among them, which
    // fuzzy-searches the whole application list on a miss -- run again on each window
    // that opened, closed or took focus.
    property var entryPool: ({})

    readonly property TaskbarAppEntry separatorEntry: appEntryComp.createObject(root, {
        appId: "SEPARATOR",
        toplevels: [],
        pinned: false
    })

    function heldEntry(appId, toplevels) {
        var entry = root.entryPool[appId];
        if (!entry) {
            entry = appEntryComp.createObject(root, {
                appId: appId,
                toplevels: toplevels,
                pinned: root.isPinned(appId)
            });
            root.entryPool[appId] = entry;
            return entry;
        }
        entry.toplevels = toplevels;
        entry.pinned = root.isPinned(appId);
        return entry;
    }

    // What a taskbar does, as opposed to how it looks. Every environment that has
    // one draws it its own way and asks here what to show and what a click means,
    // so the same application behaves the same under any of them.

    function addressOf(toplevel): string {
        return HyprlandData.clientForToplevel(toplevel)?.address ?? "";
    }

    /** Where a window belongs: its workspace, or the one it goes back to while minimised. */
    function workspaceOf(toplevel): int {
        const client = HyprlandData.clientForToplevel(toplevel);
        if (!client)
            return -1;
        const origin = Minimize.originOf(client);
        return origin > 0 ? origin : client.workspace.id;
    }

    function isMinimized(toplevel): bool {
        return Minimize.isMinimized(root.addressOf(toplevel));
    }

    /** The monitor a window belongs on: that of its workspace, or of the one it goes back to while minimised. */
    function monitorOf(toplevel): int {
        const client = HyprlandData.clientForToplevel(toplevel);
        if (!client)
            return -1;
        const workspace = root.workspaceOf(toplevel);
        return Hyprland.workspaces.values.find(candidate => candidate.id === workspace)?.monitor?.id ?? client.monitor;
    }

    function windowsOn(entry, workspaceId: int): var {
        return entry.toplevels.filter(toplevel => root.workspaceOf(toplevel) === workspaceId);
    }

    /**
     * What to show for one workspace: every pinned application, and the others
     * that have a window there, minimised ones included. Each comes with the
     * windows it has on that workspace, in the order of `apps`, pinned first.
     */
    function appsOn(workspaceId: int): var {
        return root.appsMatching(toplevel => root.workspaceOf(toplevel) === workspaceId);
    }

    /**
     * The same for any choice of windows: every pinned application, and the
     * others with a window the test lets through, each with those windows.
     */
    function appsMatching(test): var {
        const shown = [];
        for (const entry of root.apps) {
            if (entry.appId === "SEPARATOR")
                continue;
            const windows = entry.toplevels.filter(test);
            if (!entry.pinned && windows.length === 0)
                continue;
            shown.push({
                appId: entry.appId,
                entry: entry,
                pinned: entry.pinned,
                windows: windows
            });
        }
        return shown;
    }

    function launch(appId: string) {
        AppSearch.entryFor(appId)?.execute();
    }

    /**
     * Gives a window focus and raises it.
     *
     * Not through the toplevel's own activate(): Hyprland 0.56 ignores that
     * request whatever focus_on_activate says, so a click on a window that was
     * not in front did nothing at all, and cycling a group never left the
     * window it started on. The compositor's own dispatchers do it, the same
     * way a minimised window is put back. A window on another workspace brings
     * that workspace with it.
     */
    function focusWindow(toplevel) {
        const address = root.addressOf(toplevel);
        if (!/^0x[0-9a-f]+$/.test(address))
            return;
        const target = `window = "address:${address}"`;
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.dispatch(hl.dsp.focus({ ${target} })) hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", ${target} }))`]);
    }

    /** Asks a window to close, through the compositor like focusing it. */
    function closeWindow(toplevel) {
        const address = root.addressOf(toplevel);
        if (!/^0x[0-9a-f]+$/.test(address))
            return;
        Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.window.close({ window = "address:${address}" }))`]);
    }

    /**
     * A click on an application with one window: bring it up, or put it away
     * when it is already the one in front. Putting away needs minimising, and
     * an environment without it only ever brings windows up.
     */
    function toggleWindow(toplevel) {
        const address = root.addressOf(toplevel);
        if (root.isMinimized(toplevel))
            Minimize.restore(address);
        else if (toplevel.activated && Minimize.enabled)
            Minimize.minimize(address);
        else
            root.focusWindow(toplevel);
    }

    /** Brings a window to the front, putting it back first if it was minimised. */
    function bringUp(toplevel) {
        if (root.isMinimized(toplevel))
            Minimize.restore(root.addressOf(toplevel));
        else
            root.focusWindow(toplevel);
    }

    /** Brings up the window after the one in front. */
    function cycle(windows) {
        if (windows.length === 0)
            return;
        // A minimised window can keep its activated flag once focus is let go
        // of, and counting it as the one in front would skip the real one.
        const current = windows.findIndex(toplevel => toplevel.activated && !root.isMinimized(toplevel));
        root.bringUp(windows[(current + 1) % windows.length]);
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
