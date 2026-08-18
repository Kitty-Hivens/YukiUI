import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

FooterRectangle {

    // Battery button
    WBorderlessButton {
        visible: Battery.available
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12

        contentItem: Row {
            spacing: 4

            FluentIcon {
                anchors.verticalCenter: parent.verticalCenter
                icon: WIcons.batteryLevelIcon
                FluentIcon {
                    anchors.fill: parent
                    icon: WIcons.batteryIcon
                }
            }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: `${Math.round(Battery.percentage * 100) || 0}%`
            }
        }
    }

    // Settings button.
    //
    // Kept and disabled rather than removed. The reference puts a gear in this
    // corner and the footer's spacing was measured with it there, so taking it
    // out would move everything beside it. What it used to open was the other
    // family's settings window, whose only page under this family is a placeholder
    // reading "under construction" -- a button that leads to a sign saying there is
    // nothing here is worse than one that says so itself by being greyed out.
    // Give it a target when Waffle has settings of its own.
    WBorderlessButton {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 12

        enabled: false

        contentItem: FluentIcon {
            icon: "settings"
            color: Looks.colors.inactiveIcon
        }
    }
}
