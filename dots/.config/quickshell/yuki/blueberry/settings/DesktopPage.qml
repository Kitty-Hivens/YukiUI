import QtCore
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// The icons on the desktop: whether they are there, how big, in what order,
// and the folder they are the contents of.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var desktop: Config.options.blueberry.desktop
    readonly property string folderPath: FileUtils.trimFileProtocol(String(StandardPaths.standardLocations(StandardPaths.DesktopLocation)[0] ?? ""))

    spacing: ExLooks.settings.groupGap

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "desktop_mac"
            text: Translation.tr("Show desktop icons")

            ExSwitch {
                checked: root.desktop.showIcons
                onToggled: Config.options.blueberry.desktop.showIcons = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.desktop.showIcons
            glyph: "photo_size_select_large"
            text: Translation.tr("Icon size")

            SettingsChoice {
                value: root.desktop.iconSize
                options: [
                    { value: "small", text: Translation.tr("Small icons") },
                    { value: "medium", text: Translation.tr("Medium icons") },
                    { value: "large", text: Translation.tr("Large icons") }
                ]
                onPicked: size => Config.options.blueberry.desktop.iconSize = size
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.desktop.showIcons
            glyph: "sort"
            text: Translation.tr("Sort by")
            description: Translation.tr("Folders always come first")

            SettingsChoice {
                value: root.desktop.sortBy
                options: [
                    { value: "name", text: Translation.tr("Name") },
                    { value: "size", text: Translation.tr("Size") },
                    { value: "type", text: Translation.tr("Type") },
                    { value: "date", text: Translation.tr("Date modified") }
                ]
                onPicked: field => Config.options.blueberry.desktop.sortBy = field
            }
        }
    }
    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "folder"
            text: Translation.tr("Desktop folder")
            description: root.folderPath

            ExButton {
                kind: "control"
                text: Translation.tr("Open")
                onClicked: Quickshell.execDetached(["xdg-open", root.folderPath])
            }
        }
    }
}
