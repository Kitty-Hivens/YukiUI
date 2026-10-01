import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// The tray, beside the status block at the far end of the dock: the icons kept
// in view, and behind a chevron the ones kept out of the way.
GridLayout {
    id: root

    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"

    signal menuRequested(var item, Item button)
    signal overflowRequested(Item button)

    columns: vertical ? 1 : 64
    rowSpacing: 0
    columnSpacing: 0

    // Points the way the hidden icons will come out, away from the edge.
    ExButton {
        visible: TrayService.unpinnedItems.length > 0
        kind: "flat"
        implicitWidth: 28
        implicitHeight: 28
        Layout.alignment: Qt.AlignCenter
        onClicked: root.overflowRequested(this)

        ExGlyph {
            anchors.centerIn: parent
            text: root.edge === "top" ? "expand_more"
                : root.edge === "left" ? "chevron_right"
                : root.edge === "right" ? "chevron_left"
                : "expand_less"
            size: 18
        }
    }

    /** The icon at a place in the tray, counted from one. */
    function iconAt(place: int): Item {
        return icons.itemAt(place - 1);
    }

    Repeater {
        id: icons
        model: TrayService.pinnedItems

        DockTrayIcon {
            required property var modelData
            item: modelData
            onMenuRequested: button => root.menuRequested(modelData, button)
        }
    }
}
