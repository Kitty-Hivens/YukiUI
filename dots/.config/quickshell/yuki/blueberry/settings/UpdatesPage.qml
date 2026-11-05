pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.blueberry.looks

// Whether the system is up to date, what is waiting, and whether the machine goes
// and asks by itself. Asking is the one thing here that leaves the machine, so
// it is the page's own switch rather than a setting somewhere else.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var options: Config.options.updates
    readonly property bool pending: Updates.available && Updates.count > 0
    readonly property string checkedAt: Updates.lastChecked
        ? Translation.tr("Checked at %1").arg(Qt.locale().toString(Updates.lastChecked, Config.options.time.format))
        : ""

    spacing: ExLooks.settings.groupGap

    SettingsHero {
        Layout.fillWidth: true
        switchable: false
        on: root.pending
        glyph: Updates.failed ? "cloud_off" : "system_update_alt"
        text: !Updates.available ? Translation.tr("Cannot check for updates")
            : Updates.checking ? Translation.tr("Checking...")
            : Updates.failed ? Translation.tr("Could not check")
            : Updates.lastChecked === null ? Translation.tr("Not checked yet")
            : root.pending ? Translation.tr("%1 packages can be updated").arg(Updates.count)
            : Translation.tr("Everything is up to date")
        subtitle: !Updates.available ? Translation.tr("checkupdates is not installed") : root.checkedAt

        ExButton {
            visible: Updates.available
            anchors.verticalCenter: parent.verticalCenter
            kind: "control"
            enabled: !Updates.checking
            text: Translation.tr("Check")
            onClicked: Updates.refresh()
        }
        ExButton {
            visible: root.pending
            anchors.verticalCenter: parent.verticalCenter
            kind: "accent"
            text: Translation.tr("Update")
            onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.update])
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: root.pending

        SettingsExpander {
            id: list

            Layout.fillWidth: true
            glyph: "inventory_2"
            text: Translation.tr("What will be updated")

            // Made as it opens: there can be hundreds, and most visits only
            // want the number.
            Repeater {
                model: list.expanded ? Updates.packages : []

                SettingsCard {
                    required property var modelData

                    Layout.fillWidth: true
                    flat: true
                    text: modelData.name

                    ExText {
                        text: `${modelData.from} → ${modelData.to}`
                        font.pixelSize: ExLooks.settings.small
                        dim: true
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "schedule"
            text: Translation.tr("Check by itself")
            description: Translation.tr("Fetches the package lists from the mirrors")

            ExSwitch {
                checked: root.options.enableCheck
                onToggled: Config.options.updates.enableCheck = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.options.enableCheck
            glyph: "timer"
            text: Translation.tr("How often")

            SettingsNumber {
                from: 15
                to: 1440
                stepSize: 15
                unit: Translation.tr("min")
                value: root.options.checkInterval
                onEdited: value => Config.options.updates.checkInterval = value
            }
        }
    }
}
