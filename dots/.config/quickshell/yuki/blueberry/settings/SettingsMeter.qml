import QtQuick

import qs.blueberry.looks

// How full something is, read only: thin and without a knob, so it is not taken
// for a slider.
Rectangle {
    id: root

    property real value: 0
    property bool warn: false

    property bool settled: false
    Component.onCompleted: Qt.callLater(() => root.settled = true)

    implicitWidth: 120
    implicitHeight: 4
    radius: 2
    color: ExLooks.settings.sunken

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, root.value))
        height: parent.height
        radius: parent.radius
        color: root.warn ? ExLooks.colors.warning : ExLooks.colors.textDim

        // Not as it comes up, where it would grow from nothing on every page.
        Behavior on width {
            enabled: root.settled
            NumberAnimation {
                duration: ExLooks.motion.normal
                easing.type: Easing.OutCubic
            }
        }
    }
}
