import QtQuick
import QtQuick.Controls

// A button of a toolbar: a glyph, and a word beside it when it needs one, on
// a tonal plate while it is on.
AbstractButton {
    id: tool

    ExPrimaryOnly {
        z: 1
    }

    property string glyph
    property bool toggled: false

    implicitWidth: tool.text.length > 0 ? row.implicitWidth + 2 * ExLooks.spacing.m : 40
    implicitHeight: 40
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity

    background: Rectangle {
        radius: ExLooks.radius.control
        color: tool.toggled ? ExLooks.colors.tonal : "transparent"

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: tool.hovered && tool.enabled
            pressed: tool.down
        }
    }
    contentItem: Item {
        Row {
            id: row

            anchors.centerIn: parent
            spacing: ExLooks.spacing.s

            ExGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: tool.glyph
                size: 20
                fill: tool.toggled ? 1 : 0
                color: tool.toggled ? ExLooks.colors.tonalInk : ExLooks.colors.text
            }
            ExText {
                visible: tool.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: tool.text
                role: "label"
                color: tool.toggled ? ExLooks.colors.tonalInk : ExLooks.colors.text
            }
        }
    }
}
