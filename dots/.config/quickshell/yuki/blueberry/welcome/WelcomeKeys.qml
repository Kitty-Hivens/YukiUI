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

                Keycap {}
            }
        }
    }

    // A key as it stands on the keyboard: a face over a deeper edge.
    component Keycap: Item {
        id: cap

        required property string modelData
        readonly property bool arrows: cap.modelData === "arrows"

        implicitWidth: Math.max(28, (cap.arrows ? arrowRow.implicitWidth : label.implicitWidth) + 16)
        implicitHeight: 28

        Rectangle {
            anchors.fill: parent
            radius: 7
            color: ExLooks.colors.border
        }
        Rectangle {
            width: parent.width
            height: parent.height - 2
            radius: 7
            color: ExLooks.settings.sunken
            border.width: 1
            border.color: ExLooks.colors.border

            ExText {
                id: label
                anchors.centerIn: parent
                visible: !cap.arrows
                text: cap.modelData
                font.pixelSize: ExLooks.settings.small
                font.weight: ExLooks.font.weightTitle
            }
            Row {
                id: arrowRow
                anchors.centerIn: parent
                visible: cap.arrows
                spacing: -2

                Repeater {
                    model: ["arrow_left_alt", "arrow_upward_alt", "arrow_downward_alt", "arrow_right_alt"]

                    ExGlyph {
                        required property string modelData
                        text: modelData
                        size: 16
                    }
                }
            }
        }
    }
}
