import QtQuick

import qs.blueberry.looks

// The tablet's surface drawn to scale, and on it the part the pen is read on.
Item {
    id: root

    property real tabletWidth: 1
    property real tabletHeight: 1
    /** { Width, Height, X, Y } in millimetres, X and Y to its middle, or null. */
    property var area: null

    readonly property real maxHeight: 150
    readonly property real scale: Math.min(root.width / root.tabletWidth, root.maxHeight / root.tabletHeight)

    implicitHeight: root.tabletHeight * root.scale

    Rectangle {
        id: surface

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.tabletWidth * root.scale
        height: root.tabletHeight * root.scale
        radius: ExLooks.settings.controlRadius
        color: ExLooks.settings.sunken
        border.width: 1
        border.color: ExLooks.colors.hairline

        Rectangle {
            visible: root.area !== null
            x: ((root.area?.X ?? 0) - (root.area?.Width ?? 0) / 2) * root.scale
            y: ((root.area?.Y ?? 0) - (root.area?.Height ?? 0) / 2) * root.scale
            width: (root.area?.Width ?? 0) * root.scale
            height: (root.area?.Height ?? 0) * root.scale
            radius: 4
            color: Qt.alpha(ExLooks.colors.accent, 0.25)
            border.width: 2
            border.color: ExLooks.colors.accent
        }
    }
}
