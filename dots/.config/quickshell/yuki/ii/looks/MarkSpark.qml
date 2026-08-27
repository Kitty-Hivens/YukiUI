import QtQuick
import qs.core
import qs.common

/**
 * The star from the middle of the Illogical Impulse mark: four crossed bars with
 * rounded ends, against the square-cut ends of the ring around it. The mark sets
 * the two against each other on purpose, so anything drawn from it keeps both.
 */
Item {
    id: root

    property color color: Appearance.colors.colPrimary
    property real barWidth: Math.min(width, height) * 0.13

    implicitWidth: 48
    implicitHeight: 48

    Repeater {
        model: [0, 45, 90, 135]

        delegate: Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: root.barWidth
            height: Math.min(root.width, root.height)
            radius: root.barWidth / 2
            color: root.color
            rotation: modelData
        }
    }
}
