import QtQuick
import QtQuick.Layouts

// A category's own page: a card for each page it leads to.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: 4

    Repeater {
        model: root.settings?.category?.pages ?? []

        SettingsCard {
            required property var modelData

            Layout.fillWidth: true
            glyph: modelData.glyph
            text: modelData.name
            description: modelData.description
            leads: true
            onClicked: root.settings.open(modelData.key)
        }
    }
}
