pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// The keys worth knowing from the first day, each as the keys themselves.
// Only ones this desktop answers: the shared binds hold more, some of them for
// panels another desktop draws.
WelcomeStep {
    id: root

    title: Translation.tr("Keys worth knowing")
    subtitle: Translation.tr("Super is the key with the Windows logo on most keyboards. Tapped on its own, it opens the search.")

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: ExLooks.spacing.m

        SettingsSection {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            title: Translation.tr("Getting around")

            KeyRow { keys: ["Super"]; text: Translation.tr("Search and applications") }
            KeyRow { keys: ["Alt", "Tab"]; text: Translation.tr("Switch windows") }
            KeyRow { keys: ["Super", "D"]; text: Translation.tr("Show the desktop") }
            KeyRow { keys: ["Super", "I"]; text: Translation.tr("Settings") }
            KeyRow { keys: ["Super", "E"]; text: Translation.tr("Files") }
            KeyRow { keys: ["Super", "Enter"]; text: Translation.tr("Terminal") }
            KeyRow { keys: ["Super", "/"]; text: Translation.tr("All the keys, any time") }
        }
        SettingsSection {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            title: Translation.tr("Windows and the screen")

            KeyRow { keys: ["Super", "arrows"]; text: Translation.tr("Snap a window") }
            KeyRow { keys: ["Super", "Q"]; text: Translation.tr("Close a window") }
            KeyRow { keys: ["Super", "V"]; text: Translation.tr("Clipboard history") }
            KeyRow { keys: ["Super", "Shift", "S"]; text: Translation.tr("Snip the screen") }
            KeyRow { keys: ["Super", "G"]; text: Translation.tr("Game bar") }
            KeyRow { keys: ["Super", "L"]; text: Translation.tr("Lock") }
            KeyRow { keys: ["Ctrl", "Alt", "Del"]; text: Translation.tr("Leave or shut down") }
        }
    }

    // What the keys do, and the keys at the far end.
    component KeyRow: SettingsCard {
        id: keyRow

        property var keys: []

        Layout.fillWidth: true

        Row {
            spacing: 4

            Repeater {
                model: keyRow.keys

                ExKeycap {
                    required property string modelData

                    text: modelData === "arrows" ? "" : modelData
                    glyphs: modelData === "arrows" ? ["arrow_left_alt", "arrow_upward_alt", "arrow_downward_alt", "arrow_right_alt"] : []
                }
            }
        }
    }
}
