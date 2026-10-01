import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower

import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.looks

// Quick settings, opened from the status block: the switches worth reaching
// without opening anything, in pages, sound and brightness, and the battery.
ExPopup {
    id: root

    readonly property var brightness: Brightness.getMonitorForScreen(root.dockWindow.screen)
    readonly property string powerProfileName: PowerProfiles.profile === PowerProfile.PowerSaver ? Translation.tr("Power saver")
        : PowerProfiles.profile === PowerProfile.Performance ? Translation.tr("Performance")
        : Translation.tr("Balanced")

    function nextPowerProfile() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (PowerProfiles.profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    /** Which switches there are, in their order. Changes only when one comes or goes. */
    readonly property var tileKeys: ["wifi", BluetoothStatus.available ? "bluetooth" : "", "nightLight", "doNotDisturb", "powerMode", "darkTheme", "keepAwake"].filter(key => key.length > 0)

    /** What a switch shows, read live from the system. */
    function tileInfo(key: string): var {
        if (key === "wifi")
            return {
                glyph: Network.materialSymbol,
                text: Translation.tr("Wi-Fi"),
                subtitle: Network.wifiEnabled ? (Network.networkName || Translation.tr("Not connected")) : Translation.tr("Off"),
                checked: Network.wifiEnabled
            };
        if (key === "bluetooth")
            return {
                glyph: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth",
                text: Translation.tr("Bluetooth"),
                subtitle: !BluetoothStatus.enabled ? Translation.tr("Off") : (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")),
                checked: BluetoothStatus.enabled
            };
        if (key === "nightLight")
            return {
                glyph: "nightlight",
                text: Translation.tr("Night Light"),
                subtitle: Hyprsunset.temperatureActive ? Translation.tr("On") : Translation.tr("Off"),
                checked: Hyprsunset.temperatureActive
            };
        if (key === "doNotDisturb")
            return {
                glyph: Notifications.silent ? "notifications_off" : "notifications",
                text: Translation.tr("Do not disturb"),
                subtitle: Notifications.silent ? Translation.tr("On") : Translation.tr("Off"),
                checked: Notifications.silent
            };
        if (key === "powerMode")
            return {
                glyph: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf" : PowerProfiles.profile === PowerProfile.Performance ? "speed" : "balance",
                text: Translation.tr("Power mode"),
                subtitle: root.powerProfileName,
                checked: PowerProfiles.profile !== PowerProfile.Balanced
            };
        // The system's mode, which the shell and the applications both follow.
        if (key === "darkTheme")
            return {
                glyph: "dark_mode",
                text: Translation.tr("Dark theme"),
                subtitle: ExLooks.dark ? Translation.tr("On") : Translation.tr("Off"),
                checked: ExLooks.dark
            };
        return {
            glyph: "coffee",
            text: Translation.tr("Keep awake"),
            subtitle: Idle.inhibit ? Translation.tr("On") : Translation.tr("Off"),
            checked: Idle.inhibit
        };
    }

    function runTile(key: string) {
        if (key === "wifi")
            Network.toggleWifi();
        else if (key === "bluetooth" && Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
        else if (key === "nightLight")
            Hyprsunset.toggleTemperature(!Hyprsunset.temperatureActive);
        else if (key === "doNotDisturb")
            Notifications.silent = !Notifications.silent;
        else if (key === "powerMode")
            root.nextPowerProfile();
        else if (key === "darkTheme")
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", ExLooks.dark ? "light" : "dark", "--noswitch"]);
        else if (key === "keepAwake")
            Idle.toggleInhibit();
    }

    padding: ExLooks.spacing.l

    motion: "panel"
    onDismissRequested: root.open = false

    ColumnLayout {
        id: column

        width: 400
        spacing: ExLooks.spacing.s

        // Three rows of switches at most, and pages beyond that, turned by
        // dragging, by scrolling or with the dots under them.
        ListView {
            id: pager

            readonly property int perPage: 6
            readonly property real tileRows: 3

            Layout.fillWidth: true
            Layout.preferredHeight: pager.tileRows * ExLooks.sizes.tileHeight + (pager.tileRows - 1) * ExLooks.spacing.s
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: ExLooks.motion.normal
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            model: Math.ceil(root.tileKeys.length / pager.perPage)

            // Scrolling up or down turns the page too, since a mouse has no
            // sideways wheel. Taken above the pages, since the list takes a
            // wheel for its own sideways scrolling and snaps straight back.
            // What a touchpad sends in small steps is added up to one notch,
            // and a page turns at most every quarter second, so one stroke
            // turns one page. Clicks and drags pass through.
            MouseArea {
                property real scrolled: 0

                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    event.accepted = true;
                    if (turnPause.running)
                        return;
                    scrolled += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                    if (Math.abs(scrolled) < 120)
                        return;
                    if (scrolled < 0)
                        pager.incrementCurrentIndex();
                    else
                        pager.decrementCurrentIndex();
                    scrolled = 0;
                    turnPause.restart();
                }

                Timer {
                    id: turnPause
                    interval: 250
                }
            }

            delegate: GridLayout {
                id: page

                required property int index

                width: pager.width
                height: pager.height
                columns: 2
                columnSpacing: ExLooks.spacing.s
                rowSpacing: ExLooks.spacing.s

                Repeater {
                    model: root.tileKeys.slice(page.index * pager.perPage, (page.index + 1) * pager.perPage)

                    // State comes from the system, so a click asks for the
                    // change and the tile follows what actually happened.
                    ExToggleTile {
                        required property string modelData
                        readonly property var info: root.tileInfo(modelData)

                        // Half the page each, even alone in its row.
                        Layout.preferredWidth: (page.width - page.columnSpacing) / 2
                        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                        checkable: false
                        glyph: info.glyph
                        text: info.text
                        subtitle: info.subtitle
                        checked: info.checked
                        onClicked: root.runTile(modelData)
                    }
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            visible: pager.count > 1
            spacing: ExLooks.spacing.xs

            Repeater {
                model: pager.count

                AbstractButton {
                    id: dot

                    required property int index
                    readonly property bool current: dot.index === pager.currentIndex

                    implicitWidth: 18
                    implicitHeight: 18
                    hoverEnabled: true
                    onClicked: pager.currentIndex = dot.index

                    contentItem: Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: dot.current ? 16 : 6
                            height: 6
                            radius: 3
                            color: dot.current ? ExLooks.colors.accent : ExLooks.colors.textDim
                            opacity: dot.current || dot.hovered ? 1 : 0.5

                            Behavior on width {
                                NumberAnimation { duration: ExLooks.motion.fast }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.s
            spacing: ExLooks.spacing.s

            ExButton {
                kind: "flat"
                glyph: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
                onClicked: {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                }
            }
            ExSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: Audio.setDeviceVolume(Audio.sink, value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.brightness !== null && root.brightness !== undefined
            spacing: ExLooks.spacing.s

            Item {
                implicitWidth: ExLooks.sizes.control
                implicitHeight: ExLooks.sizes.control

                ExGlyph {
                    anchors.centerIn: parent
                    text: "brightness_6"
                    size: 18
                }
            }
            ExSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: root.brightness?.brightness ?? 0
                onMoved: root.brightness?.setBrightness(value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.s
            spacing: ExLooks.spacing.s

            ExGlyph {
                visible: Battery.available
                text: Battery.isCharging ? "battery_charging_full" : "battery_5_bar"
                size: 18
            }
            ExText {
                Layout.fillWidth: true
                text: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : ""
                role: "label"
            }
            ExButton {
                kind: "control"
                glyph: "settings"
                onClicked: {
                    root.open = false;
                    Surfaces.open("settings", "");
                }
            }
            ExButton {
                kind: "control"
                glyph: "power_settings_new"
                onClicked: {
                    root.open = false;
                    ExStates.sessionOpen = true;
                }
            }
        }
    }
}
