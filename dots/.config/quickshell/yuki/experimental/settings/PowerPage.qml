import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

import qs.core
import qs.core.services
import qs.experimental.looks

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
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.round((seconds % 3600) / 60);
        return hours > 0 ? Translation.tr("%1 h %2 min").arg(hours).arg(minutes) : Translation.tr("%1 min").arg(minutes);
    }

    function minutes(seconds): int {
        return Math.max(1, Math.round(seconds / 60));
    }

    Component.onCompleted: Hypridle.refresh()

    spacing: ExLooks.spacing.s

    // The charge, first when there is one.
    SettingsCard {
        Layout.fillWidth: true
        visible: root.hasBattery
        glyph: Battery.isCharging ? "battery_charging_full" : "battery_5_bar"
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

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Power mode")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "bolt"
            text: Translation.tr("Power mode")
            description: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                ? Translation.tr("Held back: the machine thinks it is on a lap")
                : PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                ? Translation.tr("Held back: the machine is too warm")
                : Translation.tr("How hard the machine may run")

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
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("When left alone")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "coffee"
            text: Translation.tr("Keep awake")
            description: Translation.tr("Nothing below happens while this is on")

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
        title: Translation.tr("Battery levels")
        visible: root.hasBattery

        SettingsCard {
            Layout.fillWidth: true
            glyph: "battery_2_bar"
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
            glyph: "battery_alert"
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
            description: Config.options.battery.full > 100 ? Translation.tr("Above 100 means never: no battery reports more than a hundred") : ""

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
