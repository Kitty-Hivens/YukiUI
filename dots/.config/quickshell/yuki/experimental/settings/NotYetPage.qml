import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// A page that is listed but not built yet, saying so rather than lying empty.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: ExLooks.spacing.s

    ExGlyph {
        Layout.topMargin: ExLooks.spacing.xl
        text: "construction"
        size: 40
        color: ExLooks.colors.textDim
    }
    ExText {
        text: Translation.tr("This page is not built yet")
        font.weight: ExLooks.font.weightTitle
    }
    ExText {
        Layout.fillWidth: true
        text: root.settings?.page?.description ?? ""
        dim: true
        wrapMode: Text.Wrap
    }
}
