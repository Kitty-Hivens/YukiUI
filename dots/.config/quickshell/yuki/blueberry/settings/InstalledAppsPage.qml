pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.blueberry.looks

// Every application the launcher lists, by name, each leading to its own page:
// how it starts, its notifications, and taking it off. A search at the top
// narrows the list as it is typed.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property string summary: Translation.tr("%1 applications").arg(root.everything.length)

    readonly property var everything: [...AppSearch.list]
        .filter(entry => !entry.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property string query: filter.text.trim().toLowerCase()
    readonly property var shown: root.query.length === 0 ? root.everything
        : root.everything.filter(entry => `${entry.name} ${entry.genericName} ${entry.id}`.toLowerCase().includes(root.query))

    spacing: ExLooks.settings.groupGap

    ExTextField {
        id: filter

        Layout.preferredWidth: 360
        height: ExLooks.settings.search
        glyph: "search"
        placeholder: Translation.tr("Find an application")
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: root.shown.length > 0

        Repeater {
            model: ScriptModel {
                values: root.shown
                objectProp: "id"
            }

            SettingsCard {
                id: row

                required property var modelData

                Layout.fillWidth: true
                iconSource: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                text: row.modelData.name
                description: row.modelData.genericName || row.modelData.comment || ""
                leads: true
                onClicked: root.settings.open(`app:${row.modelData.id}`)
            }
        }
    }

    ExText {
        visible: root.shown.length === 0
        Layout.leftMargin: ExLooks.spacing.l
        text: Translation.tr("No application by that name")
        dim: true
    }
}
