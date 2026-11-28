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

    readonly property bool troubled: Updates.updateOutcome === "failed" || Updates.updateOutcome === "partial"

    /** The step the update is in, in words. */
    readonly property string stepName: ({
        "shell": "YukiUI",
        "system": Translation.tr("System packages"),
        "packages": Translation.tr("YukiUI's own packages"),
        "files": Translation.tr("Files")
    })[Updates.updateStep] ?? Translation.tr("Starting")
    readonly property string failedName: ({
        "shell": "YukiUI",
        "system": Translation.tr("System packages"),
        "packages": Translation.tr("YukiUI's own packages"),
        "files": Translation.tr("Files")
    })[Updates.updateFailedStep] ?? Translation.tr("Starting")

    /** Why YukiUI cannot be pulled now, or empty when it can. */
    readonly property string shellObstacle: Updates.shellState === "dirty" ? Translation.tr("There are changes in the repository that are not committed. Commit or stash them, and it can be pulled.")
        : Updates.shellState === "detached" ? Translation.tr("The repository is not on a branch, so there is nothing to pull into.")
        : Updates.shellState === "no-upstream" ? Translation.tr("The branch follows no remote branch, so there is nothing to pull.")
        : Updates.shellState === "diverged" ? Translation.tr("The branch and the remote have both moved on. Pulling would mean merging, which is left to you.")
        : Updates.shellState === "no-release" ? Translation.tr("Choose Development to follow every change until the first release comes out.")
        : ""

    spacing: ExLooks.settings.groupGap

    SettingsHero {
        Layout.fillWidth: true
        switchable: false
        on: root.pending || Updates.updating
        busy: Updates.updating
        glyph: Updates.updating ? "progress_activity"
            : Updates.updateOutcome === "failed" ? "error"
            : Updates.updateOutcome === "partial" ? "info"
            : Updates.failed && !Updates.shellAvailable ? "cloud_off" : "system_update_alt"
        text: Updates.updating ? Translation.tr("Updating")
            : Updates.updateOutcome === "failed" ? Translation.tr("The update stopped")
            : Updates.updateOutcome === "partial" ? Translation.tr("Not everything was updated")
            : root.checking ? Translation.tr("Checking...")
            : root.pending ? Translation.tr("Updates are ready")
            : root.neverChecked ? Translation.tr("Not checked yet")
            : Translation.tr("Everything is up to date")
        subtitle: {
            if (Updates.updating)
                return Updates.updateSteps > 1 ? Translation.tr("Step %1 of %2: %3").arg(Math.max(1, Updates.updateStepNumber)).arg(Updates.updateSteps).arg(root.stepName) : root.stepName;
            if (Updates.updateOutcome === "failed")
                return Translation.tr("Stopped at: %1").arg(root.failedName);
            if (Updates.updateOutcome === "partial")
                return Translation.tr("Could not build: %1").arg(Updates.updateNotBuilt.join(", "));
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
            visible: (Updates.available || Updates.shellAvailable) && !Updates.updating
            anchors.verticalCenter: parent.verticalCenter
            kind: "control"
            enabled: !root.checking
            text: Translation.tr("Check")
            onClicked: Updates.refreshAll()
        }
        ExButton {
            visible: (Updates.updateOutcome === "failed" || Updates.updateOutcome === "partial") && !Updates.updating
            anchors.verticalCenter: parent.verticalCenter
            kind: "control"
            text: Translation.tr("Open in terminal")
            onClicked: Updates.updateInTerminal()
        }
        ExButton {
            visible: root.pending && !Updates.updating
            anchors.verticalCenter: parent.verticalCenter
            kind: "accent"
            text: Updates.updateOutcome === "failed" || Updates.updateOutcome === "partial" ? Translation.tr("Try again") : Translation.tr("Update")
            onClicked: Updates.update()
        }
    }

    // What the update is doing, and what it said once it is over. It opens out
    // of the line between its neighbours rather than pushing them apart at once.
    Item {
        id: progress

        property real shown: Updates.updating || Updates.updateOutcome.length > 0 ? 1 : 0
        Behavior on shown {
            NumberAnimation {
                duration: ExLooks.motion.slow
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ExLooks.motion.decelerate
            }
        }

        Layout.fillWidth: true
        Layout.preferredHeight: progressSection.implicitHeight * progress.shown
        Layout.topMargin: -root.spacing * (1 - progress.shown)
        visible: progress.shown > 0
        opacity: progress.shown
        clip: progress.shown < 1

        SettingsSection {
            id: progressSection

            width: parent.width
            title: Translation.tr("Progress")

            SettingsCard {
                Layout.fillWidth: true
                visible: Updates.updating
                glyph: "downloading"
                text: Updates.updateDetail.length === 0 ? Translation.tr("Starting")
                    : Updates.updatePackage.length > 0 && !Updates.updateDetail.includes(Updates.updatePackage) ? `${Updates.updatePackage}: ${Updates.updateDetail}`
                    : Updates.updateDetail
                description: Updates.shellAvailable ? Translation.tr("You can close this window. The shell reloads by itself near the end")
                    : Translation.tr("You can close this window")

                // How far through the packages, where it says so, and only that
                // something goes on where it does not.
                Item {
                    implicitWidth: 120
                    implicitHeight: 4

                    SettingsMeter {
                        anchors.fill: parent
                        visible: Updates.updateShare >= 0
                        value: Math.max(0, Updates.updateShare)
                    }
                    ExProgressLine {
                        anchors.fill: parent
                        visible: Updates.updateShare < 0
                        running: Updates.updating && Updates.updateShare < 0
                    }
                }
            }
            SettingsExpander {
                id: output

                Layout.fillWidth: true
                visible: Updates.updateNotes.length > 0 || (root.troubled && Updates.updateLog.length > 0)
                expanded: root.troubled
                glyph: Updates.updateOutcome === "done" ? "check_circle" : "terminal"
                text: root.troubled ? Translation.tr("What went wrong")
                    : Updates.updateOutcome === "done" ? Translation.tr("The update is done") : Translation.tr("Details of the update")

                ExText {
                    Layout.fillWidth: true
                    Layout.margins: ExLooks.settings.rowPadding
                    Layout.leftMargin: 2 * ExLooks.settings.rowPadding + ExLooks.settings.rowChip
                    // In words, and as the program said it where it stopped.
                    text: (!output.expanded ? [] : root.troubled ? Updates.updateLog.slice(-20) : Updates.updateNotes.slice(-12)).join("\n")
                    font.pixelSize: ExLooks.settings.small
                    font.family: root.troubled ? "monospace" : ExLooks.font.family
                    wrapMode: Text.WrapAnywhere
                    dim: true
                }
                ExButton {
                    Layout.leftMargin: 2 * ExLooks.settings.rowPadding + ExLooks.settings.rowChip
                    Layout.bottomMargin: ExLooks.settings.rowPadding
                    kind: "control"
                    text: Translation.tr("Open the whole log")
                    onClicked: Qt.openUrlExternally(`file://${Updates.updateLogPath}`)
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "YukiUI"

        // What this copy is and what it follows. Changed here, the channel
        // takes effect on the next update.
        SettingsCard {
            Layout.fillWidth: true
            visible: Updates.shellAvailable && Updates.shellChannel.length > 0
            glyph: "sell"
            text: Updates.shellVersion.length > 0 ? Translation.tr("Version %1").arg(Updates.shellVersion) : Translation.tr("No release yet")
            description: Updates.shellChannel === "main" ? Translation.tr("Development: every change on the main branch, as it lands")
                : Updates.shellSince > 0 ? Translation.tr("Stable: releases only. This copy is past the latest one, so it waits for the next")
                : Translation.tr("Stable: releases only")

            SettingsChoice {
                enabled: !Updates.updating
                value: Updates.shellChannel
                options: [
                    { value: "stable", text: Translation.tr("Stable") },
                    { value: "main", text: Translation.tr("Development") }
                ]
                onPicked: channel => Updates.setChannel(channel)
            }
        }

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
            text: Updates.shellChannel === "stable" && Updates.shellLatest.length > 0 ? Translation.tr("Release %1: %2 changes").arg(Updates.shellLatest).arg(Updates.shellBehind)
                : Translation.tr("%1 new changes").arg(Updates.shellBehind)
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
                : Updates.shellState === "no-release" ? Translation.tr("There is no release to follow yet")
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
                    description: modelData.aur ? "AUR" : ""

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
            glyph: "handyman"
            text: Translation.tr("AUR packages")
            description: Translation.tr("Counted and upgraded with the rest. The AUR is told their names, and they are built from scripts that other people wrote, without showing them first")

            ExSwitch {
                checked: root.options.aur
                onToggled: Config.options.updates.aur = checked
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
