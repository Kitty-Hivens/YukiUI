import QtQuick
import Quickshell

import qs.core.services
import qs.experimental.looks

// What a right click on a dock button offers: the actions its desktop entry
// declares, another instance, pinning, and for the windows it has on the
// workspace, minimising or putting back and closing, all of them at once.
ExPopup {
    id: root

    readonly property var entry: root.opener?.entry ?? null
    readonly property var windows: root.opener?.windows ?? []
    readonly property var desktopEntry: root.entry ? AppSearch.entryFor(root.entry.appId) : null
    readonly property bool pinned: root.entry?.pinned ?? false

    readonly property var items: {
        const list = [];
        for (const action of root.desktopEntry?.actions ?? [])
            list.push({ key: `action:${action.name}`, text: action.name, glyph: "", run: () => action.execute() });
        if (list.length > 0)
            list.push({ key: "separator:actions", separator: true });
        if (root.desktopEntry)
            list.push({ key: "launch", text: root.desktopEntry.name, glyph: "open_in_new", run: () => root.desktopEntry.execute() });
        if (root.entry)
            list.push({
                key: "pin",
                text: root.pinned ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock"),
                glyph: root.pinned ? "keep_off" : "keep",
                run: () => TaskbarApps.togglePin(root.entry.appId)
            });
        if (root.windows.length > 0)
            list.push({ key: "separator:windows", separator: true });
        if (root.windows.length > 0) {
            const windows = root.windows;
            const several = windows.length > 1;
            // Minimising takes whatever is still in sight. Once all of it is
            // minimised, the same place puts it all back.
            const inSight = windows.filter(toplevel => !TaskbarApps.isMinimized(toplevel));
            list.push(inSight.length > 0 ? {
                key: "minimize",
                text: several ? Translation.tr("Minimize all windows") : Translation.tr("Minimize"),
                glyph: "minimize",
                run: () => Minimize.minimizeMany(inSight.map(toplevel => TaskbarApps.addressOf(toplevel)))
            } : {
                key: "minimize",
                text: several ? Translation.tr("Restore all windows") : Translation.tr("Restore"),
                glyph: "open_in_full",
                run: () => Minimize.restoreMany(windows.map(toplevel => TaskbarApps.addressOf(toplevel)))
            });
            list.push({
                key: "close",
                text: windows.length > 1 ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                glyph: "close",
                destructive: true,
                run: () => windows.forEach(toplevel => TaskbarApps.closeWindow(toplevel))
            });
        }
        return list;
    }

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    Column {
        width: ExLooks.sizes.menuWidth

        // Kept by key, so the items stay as they are while the windows
        // change: made anew, the one under the pointer lost its hover.
        Repeater {
            model: ScriptModel {
                values: root.items
                objectProp: "key"
            }

            Loader {
                id: slot

                required property var modelData

                width: parent.width
                sourceComponent: slot.modelData.separator ? separator : item

                Component {
                    id: separator
                    ExMenuSeparator {}
                }

                Component {
                    id: item
                    ExMenuItem {
                        text: slot.modelData.text
                        glyph: slot.modelData.glyph
                        destructive: slot.modelData.destructive ?? false
                        onClicked: {
                            root.open = false;
                            slot.modelData.run();
                        }
                    }
                }
            }
        }
    }
}
