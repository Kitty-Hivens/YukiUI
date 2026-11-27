import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs.core
import qs.core.services
import qs.blueberry.looks

// What the machine runs on, how hard it may run, and when it may stop: the
// three trade against each other, so they share a page.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property bool hasBattery: Battery.available

    function duration(seconds): string {
        if (!seconds || seconds <= 0)
            return "";
        // Rounded as a whole, so 59.5 minutes is an hour and not "60 min".
        const total = Math.round(seconds / 60);
        const hours = Math.floor(total / 60);
        const minutes = total % 60;
        return hours > 0 ? Translation.tr("%1 h %2 min").arg(hours).arg(minutes) : Translation.tr("%1 min").arg(minutes);
    }

    function minutes(seconds): int {
        return Math.max(1, Math.round(seconds / 60));
    }

    Component.onCompleted: Hypridle.refresh()

    // The power saving of the PCI Express links, the kernel's ASPM policy, as
    // it stands now: the one in brackets of those it offers. Nothing is shown
    // where the kernel has no such thing, or nothing to change it with is
    // installed.
    readonly property string pciePolicy: (pcieFile.text().match(/\[(\w+)\]/) ?? [])[1] ?? ""
    readonly property bool pcieOffered: root.pciePolicy.length > 0 && pcieHelper.installed
    /** Why the last change did not go through, or empty. */
    property string pcieProblem: ""

    FileView {
        id: pcieFile
        path: "/sys/module/pcie_aspm/parameters/policy"
        blockLoading: true
        printErrors: false
    }
    Process {
        id: pcieHelper
        property bool installed: false
        running: true
        command: ["test", "-x", "/usr/lib/yuki/yuki-pcie"]
        onExited: exitCode => pcieHelper.installed = exitCode === 0
    }
    Process {
        id: pcieSetter
        property string wanted: ""
        command: ["bash", "-c", 'if command -v sudo > /dev/null && sudo -n true 2> /dev/null; then sudo -n /usr/lib/yuki/yuki-pcie set "$1"; else pkexec /usr/lib/yuki/yuki-pcie set "$1"; fi', "pcie", pcieSetter.wanted]
        onExited: exitCode => {
            pcieFile.reload();
            // 126 and 127 are the prompt dismissed, which is no problem.
            root.pcieProblem = exitCode === 0 || exitCode === 126 || exitCode === 127 ? ""
                : Translation.tr("The firmware of this machine does not let it be changed");
        }
    }

    spacing: ExLooks.settings.groupGap

    SettingsSection {
        Layout.fillWidth: true

        // The charge, first when there is one.
        SettingsCard {
            Layout.fillWidth: true
            visible: root.hasBattery
            glyph: Battery.isCharging ? "battery_android_frame_bolt" : "battery_android_frame_5"
            text: `${Math.round(Battery.percentage * 100)}%  ·  ${Battery.isCharging ? Translation.tr("Charging") : Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery")}`
            description: {
                const parts = [];
                const left = root.duration(Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty);
                if (left.length > 0)
                    parts.push(Battery.isCharging ? Translation.tr("%1 until full").arg(left) : Translation.tr("%1 left").arg(left));
                if (Battery.health > 0)
                    parts.push(Translation.tr("Health %1%").arg(Math.round(Battery.health)));
                if (Battery.energyRate > 0)
                    parts.push(Translation.tr("%1 W").arg(Battery.energyRate.toFixed(1)));
                return parts.join("  ·  ");
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "bolt"
            text: Translation.tr("Power mode")
            description: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                ? Translation.tr("Held back: the machine thinks it is on a lap")
                : PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                ? Translation.tr("Held back: the machine is too warm")
                : ""

            SettingsChoice {
                value: PowerProfiles.profile
                options: {
                    const list = [
                        { value: PowerProfile.PowerSaver, text: Translation.tr("Power saver") },
                        { value: PowerProfile.Balanced, text: Translation.tr("Balanced") }
                    ];
                    // Offered only where the daemon has one.
                    if (PowerProfiles.hasPerformanceProfile)
                        list.push({ value: PowerProfile.Performance, text: Translation.tr("Performance") });
                    return list;
                }
                onPicked: profile => PowerProfiles.profile = profile
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: root.pcieOffered
            glyph: "memory"
            text: Translation.tr("PCI Express power saving")
            description: root.pcieProblem.length > 0 ? root.pcieProblem
                : Translation.tr("Turn it off if a disk or a card stalls as it wakes. Uses more battery")

            SettingsChoice {
                enabled: !pcieSetter.running
                value: root.pciePolicy === "powersupersave" ? "powersave" : root.pciePolicy
                options: [
                    { value: "default", text: Translation.tr("Automatic") },
                    { value: "powersave", text: Translation.tr("On") },
                    { value: "performance", text: Translation.tr("Off") }
                ]
                onPicked: policy => {
                    pcieSetter.wanted = policy;
                    pcieSetter.running = true;
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("When left alone")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "coffee"
            text: Translation.tr("Keep awake")
            description: root.shell?.reachable ?? true ? Translation.tr("Nothing below happens while this is on")
                : Translation.tr("The shell is not answering, so this cannot be changed now")

            // Held by the shell, not by this window.
            ExSwitch {
                checked: root.shell?.keepAwake ?? false
                onToggled: root.shell.setKeepAwake(checked)
            }
        }

        Repeater {
            model: [
                { kind: "lock", glyph: "lock", text: Translation.tr("Lock the screen after") },
                { kind: "screenOff", glyph: "desktop_access_disabled", text: Translation.tr("Turn the screen off after") },
                { kind: "suspend", glyph: "bedtime", text: Translation.tr("Suspend after") }
            ]

            // Written into hypridle.conf. Switched off, a timing is commented
            // out rather than deleted, so it comes back as it was.
            SettingsCard {
                id: timing

                required property var modelData
                readonly property bool on: Hypridle.state(timing.modelData.kind) === "on"

                Layout.fillWidth: true
                glyph: timing.modelData.glyph
                text: timing.modelData.text
                description: Hypridle.unreachable.includes(timing.modelData.kind) ? Translation.tr("Never happens: the machine suspends first") : ""

                SettingsNumber {
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: timing.on && !Hypridle.busy
                    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity
                    from: 1
                    to: 240
                    unit: Translation.tr("min")
                    value: root.minutes(Hypridle.seconds(timing.modelData.kind))
                    onEdited: value => Hypridle.setSeconds(timing.modelData.kind, value * 60)
                }
                ExSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: !Hypridle.busy
                    checked: timing.on
                    onToggled: Hypridle.setEnabled(timing.modelData.kind, checked)
                }
            }
        }

        // Said out loud rather than left to be found: nothing above happens
        // without the daemon.
        SettingsCard {
            Layout.fillWidth: true
            visible: !Hypridle.running
            glyph: "error"
            text: Translation.tr("hypridle is not running, so none of this happens")

            ExButton {
                kind: "accent"
                text: Translation.tr("Start it")
                enabled: !Hypridle.busy
                onClicked: Hypridle.restart()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("The shell")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "rocket_launch"
            text: Translation.tr("Keep the shell ready")
            description: Translation.tr("Panels open at once, after a game too. Keeps more of the shell in memory")

            ExSwitch {
                checked: Config.options.blueberry.keepReady
                onToggled: Config.options.blueberry.keepReady = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Battery levels")
        visible: root.hasBattery

        SettingsCard {
            Layout.fillWidth: true
            glyph: "battery_android_frame_2"
            text: Translation.tr("Warn at")

            SettingsNumber {
                from: 0
                to: 100
                stepSize: 5
                unit: "%"
                value: Config.options.battery.low
                onEdited: value => Config.options.battery.low = value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "battery_android_frame_alert"
            text: Translation.tr("Warn urgently at")

            SettingsNumber {
                from: 0
                to: 100
                unit: "%"
                value: Config.options.battery.critical
                onEdited: value => Config.options.battery.critical = value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "bedtime"
            text: Translation.tr("Suspend at")

            SettingsNumber {
                anchors.verticalCenter: parent.verticalCenter
                enabled: Config.options.battery.automaticSuspend
                opacity: enabled ? 1 : ExLooks.colors.disabledOpacity
                from: 0
                to: 100
                unit: "%"
                value: Config.options.battery.suspend
                onEdited: value => Config.options.battery.suspend = value
            }
            ExSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: Config.options.battery.automaticSuspend
                onToggled: Config.options.battery.automaticSuspend = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "charger"
            text: Translation.tr("Count as charged at")
            description: Config.options.battery.full > 100 ? Translation.tr("Above 100 means never") : ""

            SettingsNumber {
                from: 0
                to: 101
                unit: "%"
                value: Config.options.battery.full
                onEdited: value => Config.options.battery.full = value
            }
        }
    }
}
