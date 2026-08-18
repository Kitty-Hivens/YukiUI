import QtQuick
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.waffle.looks
import qs.waffle.bar

WButton {
    id: root

    property alias iconName: iconContent.icon
    property alias iconSize: iconContent.implicitSize
    property alias monochrome: iconContent.monochrome
    implicitWidth: 40
    implicitHeight: 40

    contentItem: Item {
        FluentIcon {
            id: iconContent
            anchors.centerIn: parent
            implicitSize: 18
            icon: root.iconName
        }
    }
}
