import QtQuick
import QtQuick.Layouts

/** A single line of text to type into, with a glyph before it. */
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property string glyph: ""
    property color glyphColor: ExLooks.colors.textDim
    /** Controls drawn inside the field after the text, such as a button to show a password. */
    property alias trailing: trailingSlot.data

    implicitHeight: 40
    radius: ExLooks.radius.control
    color: ExLooks.colors.surfaceSunken
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? ExLooks.colors.accent : ExLooks.colors.border

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ExLooks.spacing.m
        anchors.rightMargin: ExLooks.spacing.m
        spacing: ExLooks.spacing.s

        ExGlyph {
            visible: root.glyph.length > 0
            text: root.glyph
            size: 18
            color: root.glyphColor
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TextInput {
                id: input
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: ExLooks.colors.text
                selectionColor: ExLooks.colors.tonal
                selectedTextColor: ExLooks.colors.tonalInk
                font.family: ExLooks.font.family
                font.pixelSize: ExLooks.font.body
            }
            ExText {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: root.placeholder
                dim: true
            }
        }

        Row {
            id: trailingSlot
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: -ExLooks.spacing.xs
        }
    }
}
