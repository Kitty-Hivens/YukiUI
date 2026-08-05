pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
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
            if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

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
                pinned: false,
                toplevels: []
            }));
            map.get(toplevel.appId.toLowerCase()).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push(appEntryComp.createObject(null, { appId: key, toplevels: value.toplevels, pinned: value.pinned }));
        }

        return values;
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
