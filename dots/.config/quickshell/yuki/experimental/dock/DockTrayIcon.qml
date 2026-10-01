import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs.experimental.looks

// One tray icon. A left click does what the application asks of it, or opens
// its menu when the menu is all it has, the middle button its second action,
// and a right click its menu.
Item {
    id: root

    required property SystemTrayItem item

    signal menuRequested(Item button)

    implicitWidth: 32
    implicitHeight: 32

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: event => {
            if (event.button === Qt.RightButton) {
                if (root.item.hasMenu)
                    root.menuRequested(root);
            } else if (event.button === Qt.MiddleButton) {
                root.item.secondaryActivate();
            } else if (root.item.onlyMenu && root.item.hasMenu) {
                root.menuRequested(root);
            } else {
                root.item.activate();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: ExLooks.radius.control
        color: "transparent"

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: mouse.containsMouse
            pressed: mouse.pressed
        }
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 18
        source: root.item.icon
    }

    // An application asking to be looked at, a chat with unread messages say.
    Rectangle {
        visible: root.item.status === Status.NeedsAttention
        x: root.width - width - 5
        y: 5
        width: 8
        height: 8
        radius: 4
        color: ExLooks.colors.accent
        border.width: 1.5
        border.color: ExLooks.colors.surface
    }
}
