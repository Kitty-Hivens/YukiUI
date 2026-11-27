import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// One application in the launcher's grid.
AbstractButton {
    id: root

    required property var desktopEntry

    /** A right click, with where it landed in the tile. */
    signal menuRequested(point at)

    ExPrimaryOnly {
        id: otherButtons
        z: 1
        onRightClicked: root.menuRequested(Qt.point(otherButtons.mouseX, otherButtons.mouseY))
    }

    implicitWidth: 96
    implicitHeight: 92
    hoverEnabled: true

    onClicked: {
        AppLaunch.run(root.desktopEntry);
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
            source: Quickshell.iconPath(root.desktopEntry?.icon ?? "", "application-x-executable")
        }
        ExText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 58
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.desktopEntry?.name ?? ""
            role: "caption"
        }
    }

    // The name in full, which two lines under the icon often cut, and what the
    // application is.
    ExTooltip {
        visible: root.hovered && !root.down && !ExStates.launcherMenuOpen
        title: root.desktopEntry?.name ?? ""
        detail: root.desktopEntry?.comment || root.desktopEntry?.genericName || ""
    }
}
