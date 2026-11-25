import QtQuick

/** A mouse with one of its buttons marked: which of them is meant. */
Item {
    id: root

    /** "left" or "right". */
    property string button: "left"
    readonly property bool atRight: root.button === "right"
    property color ink: ExLooks.colors.text

    implicitWidth: 14
    implicitHeight: 20

    Rectangle {
        x: root.atRight ? root.width / 2 : 1
        y: 1
        width: root.width / 2 - 1
        height: 8
        topLeftRadius: root.atRight ? 0 : 6
        topRightRadius: root.atRight ? 6 : 0
        color: ExLooks.colors.accent
    }
    Rectangle {
        anchors.fill: parent
        radius: 7
        color: "transparent"
        border.width: 1.5
        border.color: root.ink
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 1
        height: 9
        color: root.ink
    }
    Rectangle {
        y: 9
        width: parent.width
        height: 1
        color: root.ink
    }
}
