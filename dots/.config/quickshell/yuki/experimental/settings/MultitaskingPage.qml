import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// Moving between windows, as Windows' multitasking settings lay it out.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: 4

    SettingsCard {
        Layout.fillWidth: true
        glyph: "tab"
        text: Translation.tr("Alt+Tab shows")
        description: Translation.tr("The windows of the workspace on screen, or every open window")

        SettingsChoice {
            value: Config.options.experimental.switcher.windowsFrom
            options: [
                { value: "workspace", text: Translation.tr("This workspace") },
                { value: "all", text: Translation.tr("All workspaces") }
            ]
            onPicked: value => Config.options.experimental.switcher.windowsFrom = value
        }
    }
}
