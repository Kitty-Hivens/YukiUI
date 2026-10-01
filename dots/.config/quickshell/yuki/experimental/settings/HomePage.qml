import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.looks

// Where the settings open: this machine at a glance, and the settings reached
// for most often.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: ExLooks.spacing.s

    // The machine: its wallpaper, its name and what runs on it.
    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.xl

        Rectangle {
            implicitWidth: 224
            implicitHeight: 126
            radius: ExLooks.radius.tile
            color: ExLooks.colors.surfaceSunken
            clip: true

            Image {
                anchors.fill: parent
                source: Config.options.background.wallpaperPath
                sourceSize: Qt.size(448, 252)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            ExText {
                Layout.fillWidth: true
                text: SystemInfo.hostname
                font.pixelSize: 20
                font.weight: ExLooks.font.weightTitle
            }
            ExText {
                Layout.fillWidth: true
                text: SystemInfo.distroName
                dim: true
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Most used")

        SettingsCard {
            Layout.fillWidth: true
            glyph: Network.materialSymbol
            text: Translation.tr("Wi-Fi")
            description: Network.wifiEnabled ? (Network.networkName || Translation.tr("Not connected")) : Translation.tr("Off")
            leads: true
            onClicked: root.settings.open("wifi")
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "bluetooth"
            text: Translation.tr("Bluetooth")
            description: !BluetoothStatus.enabled ? Translation.tr("Off")
                : (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected"))
            leads: true
            onClicked: root.settings.open("bluetooth")
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "dark_mode"
            text: Translation.tr("Dark theme")
            description: Translation.tr("For the shell and the applications alike")

            ExSwitch {
                checked: ExLooks.dark
                onToggled: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", checked ? "dark" : "light", "--noswitch"])
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "dock_to_bottom"
            text: Translation.tr("Dock")
            description: Translation.tr("Edge, style, alignment")
            leads: true
            onClicked: root.settings.open("dock")
        }
    }
}
