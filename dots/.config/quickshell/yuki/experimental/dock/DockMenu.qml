import QtQuick

import qs.core.services
import qs.experimental.looks

// What a right click on the dock itself offers, away from any button: the
// desktop, and the dock's own settings, as a right click on the Windows
// taskbar does.
ExPopup {
    id: root

    /** The workspace the dock shows, for showing its desktop. */
    property int workspaceId: -1

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    Column {
        width: ExLooks.sizes.menuWidth

        ExMenuItem {
            width: parent.width
            text: Translation.tr("Show the desktop")
            glyph: "desktop_windows"
            onClicked: {
                root.open = false;
                Minimize.toggleDesktop(root.workspaceId);
            }
        }
        ExMenuSeparator {
            width: parent.width
        }
        ExMenuItem {
            width: parent.width
            text: Translation.tr("Dock settings")
            glyph: "settings"
            onClicked: {
                root.open = false;
                Surfaces.open("settings", "dock");
            }
        }
    }
}
