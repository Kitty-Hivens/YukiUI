import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// What matches the search, each page a card that goes to it.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var results: root.catalogue?.search(root.settings?.query ?? "") ?? []

    spacing: 4

    Repeater {
        model: root.results

        SettingsCard {
            required property var modelData

            Layout.fillWidth: true
            glyph: modelData.glyph
            text: modelData.name
            description: `${root.catalogue.category(modelData.category)?.name ?? ""}  ·  ${modelData.description}`
            leads: true
            onClicked: root.settings.open(modelData.key)
        }
    }

    ExText {
        visible: root.results.length === 0
        Layout.topMargin: ExLooks.spacing.l
        text: Translation.tr("Nothing found")
        dim: true
    }
}
