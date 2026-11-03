import QtQuick
import QtQuick.Controls

Slider {
    id: root

    readonly property real knob: ExLooks.sizes.sliderKnob
    readonly property real centre: leftPadding + knob / 2 + visualPosition * (availableWidth - knob)

    hoverEnabled: true
    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity
    implicitWidth: 220
    implicitHeight: knob + 8
    padding: 0

    background: Item {
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.leftPadding
            width: root.availableWidth
            height: ExLooks.sizes.sliderTrack
            radius: height / 2
            color: ExLooks.colors.sliderTrack

            Rectangle {
                width: root.centre - root.leftPadding
                height: parent.height
                radius: parent.radius
                color: ExLooks.colors.accent
            }
        }
    }

    handle: Rectangle {
        x: root.centre - width / 2
        y: (root.height - height) / 2
        width: root.knob
        height: root.knob
        radius: height / 2
        color: ExLooks.colors.knob
        border.width: 1
        border.color: ExLooks.colors.knobEdge
    }
}
