import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/** A quick setting: a state that is on or off, and optionally a page behind it. */
AbstractButton {
    id: root

    property string glyph: ""
    property string subtitle: ""
    property bool hasMenu: false
    property string previewState: ""

    readonly property color fill: checked ? ExLooks.colors.accent : ExLooks.colors.control
    readonly property color ink: checked ? ExLooks.colors.accentInk : ExLooks.colors.controlInk

    checkable: true
    hoverEnabled: true
    implicitHeight: ExLooks.sizes.tileHeight
    implicitWidth: 180

    background: Rectangle {
        radius: ExLooks.radius.tile
        color: root.fill

        Behavior on color {
            ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }

        ExStateLayer {
            ink: root.ink
            hovered: root.hovered
            pressed: root.down
            previewState: root.previewState
        }
    }

    contentItem: RowLayout {
        spacing: ExLooks.spacing.m

        ExGlyph {
            Layout.leftMargin: ExLooks.spacing.m + 2
            text: root.glyph
            fill: root.checked ? 1 : 0
            color: root.ink
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            ExText {
                Layout.fillWidth: true
                text: root.text
                role: "label"
                color: root.ink
            }
            ExText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                role: "caption"
                color: root.ink
                opacity: 0.8
            }
        }
        ExGlyph {
            visible: root.hasMenu
            Layout.rightMargin: ExLooks.spacing.m
            text: "chevron_right"
            color: root.ink
            size: 18
        }
    }
}
