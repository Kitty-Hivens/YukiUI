pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// What carries the machine online, the ways online that are not Wi-Fi, the
// tunnels, and the daemon underneath when it stops answering.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property string channelName: {
        switch (Network.connectionType) {
        case "ethernet":
            return Translation.tr("Wired");
        case "wifi":
            return Translation.tr("Wi-Fi");
        case "cellular":
            return Translation.tr("Mobile broadband");
        case "bluetooth":
            return Translation.tr("Bluetooth tethering");
        }
        return "";
    }
    readonly property string reachText: {
        switch (Network.connectivity) {
        case "full":
            return Translation.tr("Internet is reachable");
        case "limited":
            return Translation.tr("Connected, but the internet is not reachable");
        case "portal":
            return Translation.tr("A sign-in page is waiting");
        case "none":
            return Translation.tr("No internet");
        }
        return "";
    }

    spacing: ExLooks.settings.groupGap

    // A saved way online that is not Wi-Fi, brought up or taken down.
    component ConnectionCard: SettingsCard {
        id: connection

        required property var modelData
        readonly property bool active: connection.modelData?.active ?? false
        readonly property bool busy: Network.busyConnectionUuid.length > 0 && Network.busyConnectionUuid === (connection.modelData?.uuid ?? "")

        Layout.fillWidth: true
        glyph: connection.modelData?.channel === "cellular" ? "signal_cellular_alt" : connection.modelData?.channel === "vpn" ? "vpn_key" : "bluetooth"
        text: connection.modelData?.name ?? Translation.tr("Unknown")
        description: connection.busy ? (connection.active ? Translation.tr("Disconnecting...") : Translation.tr("Connecting..."))
            : connection.active ? Translation.tr("Connected") : Translation.tr("Saved")

        // Alternatives to one another: two coming up at once would decide
        // between them what the machine ends up on.
        ExButton {
            kind: connection.active ? "control" : "tonal"
            enabled: !Network.connectionBusy
            text: connection.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
            onClicked: {
                if (connection.active)
                    Network.deactivateConnection(connection.modelData.uuid);
                else
                    Network.activateConnection(connection.modelData.uuid);
            }
        }
    }

    FileDialog {
        id: vpnPicker
        title: Translation.tr("Choose a VPN configuration")
        nameFilters: [`${Translation.tr("VPN configuration")} (*.conf *.ovpn)`, `${Translation.tr("All files")} (*)`]
        onAccepted: Network.importVpnConfig(FileUtils.trimFileProtocol(vpnPicker.selectedFile.toString()))
    }

    SettingsCard {
        Layout.fillWidth: true
        glyph: Network.materialSymbol
        text: Network.connected ? (Network.networkName.length > 0 ? Network.networkName : root.channelName) : Translation.tr("Not connected")
        description: Network.connected ? [root.channelName, root.reachText].filter(part => part.length > 0).join("  ·  ") : ""
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Other connections")
        visible: Network.otherConnections.length > 0

        Repeater {
            model: Network.otherConnections
            ConnectionCard {}
        }
    }

    // Shown even when empty: this is the one place a tunnel is brought into
    // existence, where the other lists show what the machine can already see.
    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("VPN")

        Repeater {
            model: Network.vpnConnections
            ConnectionCard {}
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "upload_file"
            text: Translation.tr("Import a tunnel")
            description: Network.vpnImportError.length > 0 ? Network.vpnImportError
                : Network.vpnImported.length > 0 ? Translation.tr("Imported %1").arg(Network.vpnImported)
                : Translation.tr("From a WireGuard or OpenVPN configuration file")

            ExButton {
                kind: "control"
                enabled: !Network.vpnImporting
                text: Network.vpnImporting ? Translation.tr("Importing...") : Translation.tr("Import")
                onClicked: vpnPicker.open()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Underneath")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "settings_ethernet"
            text: Translation.tr("Wi-Fi backend")
            description: `${Network.wifiBackendUnit}  ·  ${Translation.tr("Helps when scanning finds nothing")}`

            ExButton {
                kind: "control"
                enabled: !Network.wifiBackendRestarting
                text: Network.wifiBackendRestarting ? Translation.tr("Restarting...") : Translation.tr("Restart")
                onClicked: Network.restartWifiBackend()
            }
        }
    }
}
