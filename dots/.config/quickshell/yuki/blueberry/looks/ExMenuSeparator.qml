import QtQuick

Item {
    width: parent?.width ?? 0
    implicitHeight: ExLooks.spacing.s + 1

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: ExLooks.spacing.s
        width: parent.width - 2 * x
        height: 1
        color: ExLooks.colors.border
    }
}
