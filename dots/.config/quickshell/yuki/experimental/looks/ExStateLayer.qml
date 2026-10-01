import QtQuick

/**
 * The hover and press wash over a fill, in the colour drawn on that fill.
 *
 * `previewState` forces a state so the gallery can show every one of them at
 * rest, since a screenshot has no pointer.
 */
Rectangle {
    required property color ink
    property bool hovered: false
    property bool pressed: false
    property string previewState: ""

    readonly property bool showPress: previewState === "pressed" || (previewState === "" && pressed)
    readonly property bool showHover: previewState === "hover" || (previewState === "" && hovered)

    anchors.fill: parent
    radius: parent.radius
    color: ink
    opacity: showPress ? ExLooks.colors.pressOpacity : (showHover ? ExLooks.colors.hoverOpacity : 0)

    Behavior on opacity {
        NumberAnimation {
            duration: ExLooks.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ExLooks.motion.standard
        }
    }
}
