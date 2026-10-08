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
    /**
     * Room for a glyph or an icon before the text. A menu of which no entry
     * has one leaves it out, as Windows and GNOME do: kept, it was a wide
     * empty strip down the left of every such menu.
     */
    property bool iconRoom: true

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

    ExPrimaryOnly {
        z: 1
    }

    contentItem: RowLayout {
        spacing: ExLooks.spacing.m

        Item {
            visible: root.iconRoom
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
            Layout.leftMargin: root.iconRoom ? 0 : ExLooks.spacing.s + 2
            Layout.rightMargin: root.shortcut.length > 0 || root.hasSubmenu ? 0 : ExLooks.spacing.s + 2
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
