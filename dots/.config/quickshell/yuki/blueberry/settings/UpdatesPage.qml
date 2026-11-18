pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.blueberry.looks

// Whether YukiUI and the system are up to date, what is waiting in each, and
// whether the machine goes and asks by itself. One button updates both, since
// the updater takes them in the order they depend on each other. Asking is the
// one thing here that leaves the machine, so it is the page's own switch rather
// than a setting somewhere else.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var options: Config.options.updates
    readonly property bool packagesPending: Updates.available && Updates.count > 0
    readonly property bool pending: root.packagesPending || Updates.shellPending
    readonly property bool checking: Updates.checking || Updates.shellChecking
    readonly property bool neverChecked: Updates.lastChecked === null && Updates.shellLastChecked === null

    function timeOf(when): string {
        return Qt.locale().toString(when, Config.options.time.format);
    }

    /** Why YukiUI cannot be pulled now, or empty when it can. */
    readonly property string shellObstacle: Updates.shellState === "dirty" ? Translation.tr("There are changes in the repository that are not committed. Commit or stash them, and it can be pulled.")
        : Updates.shellState === "detached" ? Translation.tr("The repository is not on a branch, so there is nothing to pull into.")
        : Updates.shellState === "no-upstream" ? Translation.tr("The branch follows no remote branch, so there is nothing to pull.")
        : Updates.shellState === "diverged" ? Translation.tr("The branch and the remote have both moved on. Pulling would mean merging, which is left to you.")
        : ""

    spacing: ExLooks.settings.groupGap

    SettingsHero {
        Layout.fillWidth: true
        switchable: false
        on: root.pending
        glyph: Updates.failed && !Updates.shellAvailable ? "cloud_off" : "system_update_alt"
        text: root.checking ? Translation.tr("Checking...")
            : root.pending ? Translation.tr("Updates are ready")
            : root.neverChecked ? Translation.tr("Not checked yet")
            : Translation.tr("Everything is up to date")
        subtitle: {
            const parts = [];
            if (Updates.shellPending)
                parts.push(Translation.tr("YukiUI: %1 changes").arg(Updates.shellBehind));
            if (root.packagesPending)
                parts.push(Translation.tr("System: %1 packages").arg(Updates.count));
            if (parts.length === 0 && Updates.lastChecked !== null)
                parts.push(Translation.tr("Checked at %1").arg(root.timeOf(Updates.lastChecked)));
            return parts.join("  ·  ");
        }

        ExButton {
            visible: Updates.available || Updates.shellAvailable
            anchors.verticalCenter: parent.verticalCenter
            kind: "control"
            enabled: !root.checking
            text: Translation.tr("Check")
            onClicked: Updates.refreshAll()
        }
        ExButton {
            visible: root.pending
            anchors.verticalCenter: parent.verticalCenter
            kind: "accent"
            text: Translation.tr("Update")
            onClicked: Updates.update()
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "YukiUI"

        // Installed some other way, or before the installer wrote down where
        // it was installed from.
        SettingsCard {
            Layout.fillWidth: true
            visible: !Updates.shellAvailable
            glyph: "deployed_code"
            text: Translation.tr("Not known where YukiUI was installed from")
            description: Translation.tr("Run ./setup install from its folder once, and it is updated from here as well")
        }

        SettingsExpander {
            id: changes

            Layout.fillWidth: true
            visible: Updates.shellAvailable && Updates.shellBehind > 0
            glyph: "deployed_code_update"
            text: Translation.tr("%1 new changes").arg(Updates.shellBehind)
            description: root.shellObstacle.length > 0 ? root.shellObstacle
                : Updates.shellState === "unreachable" ? Translation.tr("Could not reach the remote just now, so these are from the last check")
                : Updates.repository

            Repeater {
                model: changes.expanded ? Updates.shellCommits : []

                SettingsCard {
                    required property var modelData

                    Layout.fillWidth: true
                    flat: true
                    text: modelData.subject

                    ExText {
                        text: modelData.hash
                        font.pixelSize: ExLooks.settings.small
                        font.family: "monospace"
                        dim: true
                    }
                }
            }
        }

        SettingsCard {
            Layout.fillWidth: true
            visible: Updates.shellAvailable && Updates.shellBehind === 0
            glyph: Updates.shellState === "unreachable" ? "cloud_off" : "deployed_code"
            text: Updates.shellChecking ? Translation.tr("Checking...")
                : Updates.shellState === "unreachable" ? Translation.tr("Could not reach the remote")
                : Updates.shellState.length === 0 ? Translation.tr("Not checked yet")
                : Translation.tr("YukiUI is up to date")
            description: root.shellObstacle.length > 0 ? root.shellObstacle
                : Updates.shellLastChecked !== null ? `${Updates.repository}  ·  ${Translation.tr("Checked at %1").arg(root.timeOf(Updates.shellLastChecked))}`
                : Updates.repository
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("System packages")

        SettingsCard {
            Layout.fillWidth: true
            visible: !root.packagesPending
            glyph: Updates.failed ? "cloud_off" : "inventory_2"
            text: !Updates.available ? Translation.tr("Cannot check for updates")
                : Updates.checking ? Translation.tr("Checking...")
                : Updates.failed ? Translation.tr("Could not check")
                : Updates.lastChecked === null ? Translation.tr("Not checked yet")
                : Translation.tr("Every package is up to date")
            description: !Updates.available ? Translation.tr("checkupdates is not installed")
                : Updates.lastChecked !== null ? Translation.tr("Checked at %1").arg(root.timeOf(Updates.lastChecked))
                : ""
        }

        SettingsExpander {
            id: list

            Layout.fillWidth: true
            visible: root.packagesPending
            glyph: "inventory_2"
            text: Translation.tr("%1 packages can be updated").arg(Updates.count)
            description: Updates.lastChecked !== null ? Translation.tr("Checked at %1").arg(root.timeOf(Updates.lastChecked)) : ""

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
        title: Translation.tr("Checking by itself")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "inventory_2"
            text: Translation.tr("System packages")
            description: Translation.tr("Fetches the package lists from the mirrors")

            ExSwitch {
                checked: root.options.enableCheck
                onToggled: Config.options.updates.enableCheck = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: Updates.shellAvailable
            glyph: "deployed_code"
            text: "YukiUI"
            description: Translation.tr("Asks the repository's remote for new commits")

            ExSwitch {
                checked: root.options.checkShell
                onToggled: Config.options.updates.checkShell = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.options.enableCheck || (Updates.shellAvailable && root.options.checkShell)
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
