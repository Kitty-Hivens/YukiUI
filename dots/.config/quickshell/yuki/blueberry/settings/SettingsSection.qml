import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// A heading and the cards under it, a little apart from one another.
ColumnLayout {
    id: root

    property string title: ""
    default property alias cards: column.data

    spacing: ExLooks.spacing.s

    ExText {
        visible: root.title.length > 0
        Layout.topMargin: ExLooks.spacing.l
        text: root.title
        font.weight: ExLooks.font.weightTitle
    }
    ColumnLayout {
        id: column
        Layout.fillWidth: true
        spacing: 4
    }
}
