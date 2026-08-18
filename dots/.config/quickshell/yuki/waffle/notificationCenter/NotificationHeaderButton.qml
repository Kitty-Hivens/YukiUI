import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.waffle.looks

WBorderlessButton {
    id: root
    Layout.fillWidth: false
    property real implicitSize: 16
    implicitWidth: implicitSize
    implicitHeight: implicitSize
    color: "transparent"
    colForeground: root.hovered && !root.pressed ? Looks.colors.fg : Looks.colors.fg1

    Behavior on colForeground {
        animation: Looks.transition.color.createObject(this)
    }

    contentItem: Item {
        FluentIcon {
            anchors.centerIn: parent
            implicitSize: root.implicitSize
            icon: root.icon.name
            color: root.colForeground
        }
    }
}
