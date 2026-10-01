import QtQuick

import qs.experimental.looks

// A few choices side by side, one of them picked.
Row {
    id: root

    /** { value, text, glyph } for each choice. */
    property var options: []
    property var value: null

    signal picked(var value)

    spacing: 4

    Repeater {
        model: root.options

        ExButton {
            required property var modelData
            kind: modelData.value === root.value ? "tonal" : "control"
            glyph: modelData.glyph ?? ""
            text: modelData.text
            onClicked: root.picked(modelData.value)
        }
    }
}
