import QtQuick

/**
 * A key as it stands on the keyboard, a face over a deeper edge, with a word on
 * it, or glyphs, the arrows say. A button of the mouse is drawn as the mouse.
 */
Item {
    id: root

    property string text: ""
    property var glyphs: []
    /** "left" or "right", for a button of the mouse. */
    property string mouse: ""
    /** The keyboard's grey for a key, set apart from the plate it is on. */
    property color face: ExLooks.settings.sunken
    property real size: 28

    implicitWidth: root.mouse.length > 0 ? 20 : Math.max(root.size, (root.glyphs.length > 0 ? glyphRow.implicitWidth : label.implicitWidth) + 16)
    implicitHeight: root.size

    ExMouseButton {
        anchors.centerIn: parent
        visible: root.mouse.length > 0
        button: root.mouse
    }
    Rectangle {
        visible: root.mouse.length === 0
        anchors.fill: parent
        radius: 7
        color: ExLooks.colors.border
    }
    Rectangle {
        visible: root.mouse.length === 0
        width: parent.width
        height: parent.height - 2
        radius: 7
        color: root.face
        border.width: 1
        border.color: ExLooks.colors.border

        ExText {
            id: label
            anchors.centerIn: parent
            visible: root.glyphs.length === 0 && root.mouse.length === 0
            text: root.text
            font.pixelSize: ExLooks.settings.small
            font.weight: ExLooks.font.weightTitle
        }
        Row {
            id: glyphRow
            anchors.centerIn: parent
            visible: root.glyphs.length > 0
            spacing: -2

            Repeater {
                model: root.glyphs

                ExGlyph {
                    required property string modelData
                    text: modelData
                    size: 16
                }
            }
        }
    }
}
