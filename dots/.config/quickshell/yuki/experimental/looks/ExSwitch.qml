import QtQuick
import QtQuick.Controls

AbstractButton {
    id: root

    property string previewState: ""
    readonly property bool showPress: previewState === "pressed" || (previewState === "" && down)
    readonly property real inset: (height - ExLooks.sizes.knob) / 2

    checkable: true
    hoverEnabled: true
    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity
    implicitWidth: ExLooks.sizes.switchWidth
    implicitHeight: ExLooks.sizes.switchHeight

    background: Rectangle {
        radius: height / 2
        color: root.checked ? ExLooks.colors.accent : ExLooks.colors.switchTrackOff

        Behavior on color {
            ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
    }

    indicator: Rectangle {
        width: ExLooks.sizes.knob + (root.showPress ? ExLooks.sizes.knobPressedStretch : 0)
        height: ExLooks.sizes.knob
        radius: height / 2
        y: root.inset
        // The outer edge stays put and a press stretches the knob inwards, so
        // it reads as leaning towards where it is about to go.
        x: root.checked ? root.width - root.inset - width : root.inset
        color: ExLooks.colors.knob

        Behavior on x {
            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
        Behavior on width {
            NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            z: -1
            radius: height / 2
            color: ExLooks.colors.knobEdge
        }
    }
}
