import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

AbstractButton {
    id: root

    property string glyph: ""
    /** A picture in the glyph's place, for entries that bring their own icon. */
    property string iconSource: ""
    property string shortcut: ""
    property bool hasSubmenu: false
    property bool destructive: false
    property string previewState: ""

    readonly property color ink: destructive ? ExLooks.colors.destructive : ExLooks.colors.text

    hoverEnabled: true
    width: parent?.width ?? implicitWidth
    implicitHeight: ExLooks.sizes.menuItem
    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity

    background: Rectangle {
        anchors.fill: parent
        radius: ExLooks.radius.menuItem
        color: "transparent"

        ExStateLayer {
            ink: root.ink
            hovered: root.hovered
            pressed: root.down
            previewState: root.previewState
        }
    }

    contentItem: RowLayout {
        spacing: ExLooks.spacing.m

        Item {
            Layout.leftMargin: ExLooks.spacing.s + 2
            implicitWidth: 18
            implicitHeight: 18

            ExGlyph {
                anchors.centerIn: parent
                visible: root.iconSource.length === 0
                text: root.glyph
                color: root.ink
                size: 18
                opacity: root.glyph.length > 0 ? 1 : 0
            }
            IconImage {
                anchors.centerIn: parent
                visible: root.iconSource.length > 0
                implicitSize: 16
                source: root.iconSource
            }
        }
        ExText {
            Layout.fillWidth: true
            text: root.text
            color: root.ink
        }
        ExText {
            visible: root.shortcut.length > 0
            text: root.shortcut
            role: "caption"
            dim: true
            Layout.rightMargin: ExLooks.spacing.s + 2
        }
        ExGlyph {
            visible: root.hasSubmenu
            Layout.rightMargin: ExLooks.spacing.s
            text: "chevron_right"
            size: 18
            color: ExLooks.colors.textDim
        }
    }
}
