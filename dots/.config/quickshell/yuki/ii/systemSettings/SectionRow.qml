pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * A way into one section of the settings, carrying what that section currently
 * holds. Full width rather than a tile: the status line is the reason to open
 * it, and a grid would crop it.
 */
Rectangle {
    id: root
    property string icon: ""
    property string title: ""
    property string description: ""
    property string status: ""

    // What the section holds is worth knowing, but not at the cost of clipping
    // what the section is: in a narrow window both ended up as ellipses.
    readonly property bool roomForStatus: root.width > 420

    signal clicked

    implicitHeight: Math.max(72, rowContent.implicitHeight + 24)
    radius: Appearance.rounding.normal
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    color: mouseArea.pressed ? Appearance.colors.colLayer2Active
        : mouseArea.containsMouse ? Appearance.colors.colLayer2Hover
        : Appearance.colors.colLayer2

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        id: rowContent
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 16
            topMargin: 12
            bottomMargin: 12
        }
        spacing: 14

        Rectangle {
            implicitWidth: 46
            implicitHeight: 46
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.hugeass
                fill: 1
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.description.length > 0
                text: root.description
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.maximumWidth: root.width * 0.4
            visible: root.status.length > 0 && root.roomForStatus
            text: root.status
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        MaterialSymbol {
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
    }
}
