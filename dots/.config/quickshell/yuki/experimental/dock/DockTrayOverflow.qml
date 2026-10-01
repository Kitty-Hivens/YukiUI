import QtQuick

import qs.core.services
import qs.experimental.looks

// The tray icons kept out of the way, in a small grid over the chevron.
ExPopup {
    id: root

    signal menuRequested(var item)

    padding: ExLooks.spacing.xs
    surfaceRadius: ExLooks.radius.tile

    onDismissRequested: root.open = false
    // Nothing left to show once every hidden icon has gone.
    onOpenChanged: {
        if (root.open && TrayService.unpinnedItems.length === 0)
            root.open = false;
    }
    Connections {
        target: TrayService
        function onUnpinnedItemsChanged() {
            if (root.open && TrayService.unpinnedItems.length === 0)
                root.open = false;
        }
    }

    Grid {
        columns: Math.min(4, Math.max(1, TrayService.unpinnedItems.length))

        Repeater {
            model: TrayService.unpinnedItems

            DockTrayIcon {
                required property var modelData
                item: modelData
                onMenuRequested: root.menuRequested(modelData)
            }
        }
    }
}
