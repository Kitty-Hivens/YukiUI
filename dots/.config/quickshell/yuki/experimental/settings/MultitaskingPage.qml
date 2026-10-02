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
        glyph: "splitscreen_left"
        text: Translation.tr("Snap windows")
        description: Translation.tr("A window dragged to a side of the screen takes that half, to a corner that quarter, to the top the whole of it")

        ExSwitch {
            checked: Config.options.experimental.snap.enabled
            onToggled: Config.options.experimental.snap.enabled = checked
        }
    }

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
