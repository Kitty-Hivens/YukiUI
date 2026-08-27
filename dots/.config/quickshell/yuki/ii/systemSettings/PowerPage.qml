pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.core.services
import qs.core
import qs.core.functions
import qs.ii.systemSettings
import qs.ii.looks
import qs.common.widgets
import qs.common

/**
 * What the machine is running on, how hard it is allowed to run, and when it is
 * allowed to stop.
 *
 * The three belong together because they trade against each other: a profile
 * that costs battery, a battery that decides when to suspend, and timings that
 * decide when either of those stops mattering.
 */
Item {
    id: root

    readonly property bool hasBattery: Battery.available
    readonly property bool charging: Battery.isCharging
    readonly property int percent: Math.round(Battery.percentage * 100)

    Component.onCompleted: Hypridle.refresh()

    function duration(seconds) {
        if (!seconds || seconds <= 0)
            return "";
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.round((seconds % 3600) / 60);
        if (hours > 0)
            return Translation.tr("%1 h %2 min").arg(hours).arg(minutes);
        return Translation.tr("%1 min").arg(minutes);
    }

    function minutes(seconds) {
        return Math.max(1, Math.round(seconds / 60));
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true
                visible: root.hasBattery

                // The charge leads the page and is the one number here with a
                // ceiling and no history, which is what the ring is for.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 18

                    MarkGauge {
                        implicitWidth: 96
                        implicitHeight: 96
                        value: Battery.percentage
                        color: Battery.isLow && !root.charging ? Appearance.colors.colError : Appearance.colors.colPrimary

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: -2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("%1%").arg(root.percent)
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.variableAxes: ({ "wght": 600 })
                                color: Appearance.colors.colOnLayer2
                            }
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.charging
                                text: "bolt"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.charging ? Translation.tr("Charging")
                                : Battery.isPluggedIn ? Translation.tr("Plugged in")
                                : Translation.tr("On battery")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.duration(root.charging ? Battery.timeToFull : Battery.timeToEmpty).length > 0
                            text: root.charging
                                ? Translation.tr("%1 until full").arg(root.duration(Battery.timeToFull))
                                : Translation.tr("%1 left").arg(root.duration(Battery.timeToEmpty))
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                FactRow {
                    // What the pack can still hold against what it left the factory
                    // with. Nothing here can change it; it explains the rest.
                    label: Translation.tr("Health")
                    value: Battery.health > 0 ? Translation.tr("%1%").arg(Math.round(Battery.health)) : ""
                }
                FactRow {
                    label: Translation.tr("Draw")
                    value: Battery.energyRate > 0 ? Translation.tr("%1 W").arg(Battery.energyRate.toFixed(1)) : ""
                }
            }

            PageHeading {
                visible: PowerProfiles.hasPerformanceProfile || root.hasBattery
                text: Translation.tr("Profile")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: PowerProfiles.hasPerformanceProfile || root.hasBattery

                ConfigSelectionArray {
                    currentValue: PowerProfiles.profile
                    options: {
                        const list = [
                            { displayName: Translation.tr("Power saver"), icon: "energy_savings_leaf", value: PowerProfile.PowerSaver },
                            { displayName: Translation.tr("Balanced"), icon: "airwave", value: PowerProfile.Balanced }
                        ];
                        // Offered only where the daemon has one: on a machine
                        // without it the choice exists and does nothing.
                        if (PowerProfiles.hasPerformanceProfile)
                            list.push({ displayName: Translation.tr("Performance"), icon: "local_fire_department", value: PowerProfile.Performance });
                        return list;
                    }
                    onSelected: newValue => PowerProfiles.profile = newValue
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                    text: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                        ? Translation.tr("Performance is being held back: the machine thinks it is on a lap")
                        : Translation.tr("Performance is being held back: the machine is too warm")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }

            PageHeading {
                text: Translation.tr("When left alone")
            }

            SystemCard {
                Layout.fillWidth: true

                ConfigSwitch {
                    id: inhibitSwitch
                    text: Translation.tr("Keep awake")
                    buttonIcon: "coffee"
                    Binding {
                        target: inhibitSwitch
                        property: "checked"
                        value: Idle.inhibit
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== Idle.inhibit)
                            Idle.toggleInhibit(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Nothing below happens while this is on")
                    }
                }

                PageDivider {}

                SettingRow {
                    icon: "lock"
                    label: Translation.tr("Lock the screen after")
                    unit: Translation.tr("min")
                    from: 1
                    to: 240
                    amount: root.minutes(Hypridle.seconds("lock"))
                    active: Hypridle.state("lock") === "on"
                    note: Hypridle.unreachable.includes("lock") ? Translation.tr("Never happens: the machine suspends first") : ""
                    noteIsProblem: true
                    holdWrites: Hypridle.busy
                    switchable: true
                    switchOn: Hypridle.state("lock") === "on"
                    switchEnabled: !Hypridle.busy
                    onAmountEdited: value => Hypridle.setSeconds("lock", value * 60)
                    onSwitched: on => Hypridle.setEnabled("lock", on)
                }
                SettingRow {
                    icon: "desktop_access_disabled"
                    label: Translation.tr("Turn the screen off after")
                    unit: Translation.tr("min")
                    from: 1
                    to: 240
                    amount: root.minutes(Hypridle.seconds("screenOff"))
                    active: Hypridle.state("screenOff") === "on"
                    note: Hypridle.unreachable.includes("screenOff") ? Translation.tr("Never happens: the machine suspends first") : ""
                    noteIsProblem: true
                    holdWrites: Hypridle.busy
                    switchable: true
                    switchOn: Hypridle.state("screenOff") === "on"
                    switchEnabled: !Hypridle.busy
                    onAmountEdited: value => Hypridle.setSeconds("screenOff", value * 60)
                    onSwitched: on => Hypridle.setEnabled("screenOff", on)
                }
                SettingRow {
                    icon: "bedtime"
                    label: Translation.tr("Suspend after")
                    unit: Translation.tr("min")
                    from: 1
                    to: 240
                    amount: root.minutes(Hypridle.seconds("suspend"))
                    active: Hypridle.state("suspend") === "on"
                    holdWrites: Hypridle.busy
                    switchable: true
                    switchOn: Hypridle.state("suspend") === "on"
                    switchEnabled: !Hypridle.busy
                    onAmountEdited: value => Hypridle.setSeconds("suspend", value * 60)
                    onSwitched: on => Hypridle.setEnabled("suspend", on)
                }

                // Said out loud rather than left to be discovered: the daemon is
                // what makes any of the three happen, and it is startable from
                // here because the alternative is a page that quietly lies.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: !Hypridle.running
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("hypridle is not running, so none of this happens")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colError
                    }
                    RippleButtonWithIcon {
                        enabled: !Hypridle.busy
                        materialIcon: "play_arrow"
                        mainText: Translation.tr("Start")
                        onClicked: Hypridle.restart()
                    }
                }

                PageNote {
                    Layout.topMargin: 8
                    text: Translation.tr("Written into hypridle.conf, and hypridle restarts on every change. Switching one off comments it out rather than deleting it, so it comes back as it was.")
                }
            }

            PageHeading {
                visible: root.hasBattery
                text: Translation.tr("Battery levels")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: root.hasBattery

                SettingRow {
                    icon: "battery_2_bar"
                    label: Translation.tr("Warn at")
                    unit: "%"
                    from: 0
                    to: 100
                    stepSize: 5
                    amount: Config.options.battery.low
                    onAmountEdited: value => Config.options.battery.low = value
                }
                SettingRow {
                    icon: "battery_alert"
                    label: Translation.tr("Warn urgently at")
                    unit: "%"
                    from: 0
                    to: 100
                    amount: Config.options.battery.critical
                    onAmountEdited: value => Config.options.battery.critical = value
                }
                SettingRow {
                    // The switch belongs on the row rather than above it: whether
                    // the machine suspends itself and the level it does it at are
                    // one setting, and asking them separately reads as two.
                    icon: "bedtime"
                    label: Translation.tr("Suspend at")
                    unit: "%"
                    from: 0
                    to: 100
                    amount: Config.options.battery.suspend
                    active: Config.options.battery.automaticSuspend
                    switchable: true
                    switchOn: Config.options.battery.automaticSuspend
                    onAmountEdited: value => Config.options.battery.suspend = value
                    onSwitched: on => Config.options.battery.automaticSuspend = on
                }
                SettingRow {
                    icon: "charger"
                    label: Translation.tr("Count as charged at")
                    // 101 is how the announcement is switched off, which is worth
                    // saying where it can be typed rather than in a comment.
                    note: Config.options.battery.full > 100 ? Translation.tr("Above 100 means never: no battery reports more than a hundred") : ""
                    unit: "%"
                    from: 0
                    to: 101
                    amount: Config.options.battery.full
                    onAmountEdited: value => Config.options.battery.full = value
                }
            }
        }
    }
}
