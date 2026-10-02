import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

import qs.experimental
import qs.experimental.looks

// One application in the launcher's grid.
AbstractButton {
    id: root

    ExPrimaryOnly {
        z: 1
    }

    required property var desktopEntry

    implicitWidth: 96
    implicitHeight: 92
    hoverEnabled: true

    onClicked: {
        root.desktopEntry.execute();
        ExStates.launcherOpen = false;
    }

    background: Rectangle {
        radius: ExLooks.radius.control
        color: "transparent"

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: root.hovered
            pressed: root.down
        }
    }

    contentItem: Item {
        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            implicitSize: 40
            source: Quickshell.iconPath(root.desktopEntry.icon, "application-x-executable")
        }
        ExText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 58
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            text: root.desktopEntry.name
            role: "caption"
        }
    }
}
