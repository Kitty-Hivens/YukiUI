import QtQuick

// Where the keyboard is, round the control it is on. Only for a focus that came
// by the keyboard: a click on a button draws none.
Rectangle {
    /** Whether the control it stands round has the keyboard's focus. */
    property bool shown: parent?.visualFocus ?? false
    /** The control's own corner, which the ring follows from outside. */
    property real cornerRadius: ExLooks.radius.control

    visible: shown
    z: 2
    anchors.fill: parent
    anchors.margins: -2
    radius: cornerRadius + 2
    color: "transparent"
    border.width: 2
    border.color: ExLooks.colors.accentText
}
