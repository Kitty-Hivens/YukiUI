import QtQuick
import QtQuick.Layouts

// A category's own page: a row for each page it leads to, in the category's
// colour, on one plate.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    SettingsSection {
        Layout.fillWidth: true

        Repeater {
            model: root.settings?.category?.pages ?? []

            SettingsCard {
                required property var modelData

                glyph: modelData.glyph
                hue: root.settings?.category?.hue ?? -1
                text: modelData.name
                description: modelData.description
                leads: true
                onClicked: root.settings.open(modelData.key)
            }
        }
    }
}
