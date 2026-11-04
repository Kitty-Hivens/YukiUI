pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks

// The radio and the networks in range. All of it from Network, the same service
// the shell's own list reads: a second view of one radio, not a second truth.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    /** The radio and the networks have been read, so the page comes in whole. */
    readonly property bool ready: Network.settled

    spacing: ExLooks.settings.groupGap

    // A network. Asking for its password, the field and what answers it take
    // the place of its buttons, on the same row.
    component NetworkCard: SettingsCard {
        id: network

        required property var modelData
        readonly property bool active: network.modelData?.active ?? false
        readonly property bool connecting: Network.wifiConnecting && Network.wifiConnectTarget === network.modelData
        readonly property bool saved: Network.savedNetworks.includes(network.modelData?.ssid ?? " ")
        readonly property bool askingPassword: network.modelData?.askingPassword ?? false
        readonly property bool needsPortal: network.active && ((network.modelData?.security ?? "").trim().length === 0 || Network.wifiStatus === "limited")
        readonly property int strength: network.modelData?.strength ?? 0
        readonly property string band: {
            const frequency = network.modelData?.frequency ?? 0;
            return frequency <= 0 ? "" : frequency >= 5900 ? "6 GHz" : frequency >= 5000 ? "5 GHz" : "2.4 GHz";
        }
        readonly property string status: {
            if (network.connecting)
                return Translation.tr("Connecting...");
            if (network.active)
                return Network.wifiStatus === "limited" ? Translation.tr("Connected, no internet") : Translation.tr("Connected");
            switch (network.modelData?.errorKind ?? "") {
            case "wrongPassword":
                return Translation.tr("Wrong password");
            case "secrets":
                return Translation.tr("Password required");
            case "notFound":
                return Translation.tr("Out of range");
            case "timeout":
                return Translation.tr("Connection timed out");
            case "failed":
                return (network.modelData?.errorDetail ?? "").length > 0 ? network.modelData.errorDetail : Translation.tr("Could not connect");
            }
            if (network.saved)
                return Translation.tr("Saved");
            return (network.modelData?.isSecure ?? false) ? Translation.tr("Secured") : Translation.tr("Not secured");
        }

        function submit() {
            if (password.text.length === 0)
                return;
            Network.connectToWifiNetwork(network.modelData, password.text);
            password.text = "";
        }

        onAskingPasswordChanged: {
            if (network.askingPassword)
                password.input.forceActiveFocus();
        }

        Layout.fillWidth: true
        glyph: network.strength > 80 ? "signal_wifi_4_bar" : network.strength > 60 ? "network_wifi_3_bar" : network.strength > 40 ? "network_wifi_2_bar" : network.strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
        hue: network.active ? 195 : -1
        text: network.modelData?.ssid ?? Translation.tr("Unknown")
        description: [network.status, network.band, (network.modelData?.isSecure ?? false) && !network.active ? (network.modelData?.security ?? "") : ""].filter(part => part.length > 0).join("  ·  ")

        ExButton {
            visible: network.needsPortal
            kind: "control"
            text: Translation.tr("Open network portal")
            onClicked: Network.openPublicWifiPortal()
        }
        SettingsForget {
            visible: network.saved && !network.askingPassword
            onConfirmed: Network.forgetWifiNetwork(network.modelData)
        }
        // One radio: while any network is being joined, none of the others can be.
        ExButton {
            visible: !network.askingPassword
            kind: network.active ? "control" : "tonal"
            enabled: !Network.wifiConnecting
            text: network.connecting ? Translation.tr("Connecting...") : network.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
            onClicked: {
                if (network.active)
                    Network.disconnectWifiNetwork();
                else
                    Network.connectToWifiNetwork(network.modelData);
            }
        }
        ExTextField {
            id: password

            visible: network.askingPassword
            width: 220
            placeholder: Translation.tr("Password")
            Component.onCompleted: password.input.echoMode = TextInput.Password

            Connections {
                target: password.input
                function onAccepted() {
                    network.submit();
                }
            }
        }
        ExButton {
            visible: network.askingPassword
            kind: "control"
            text: Translation.tr("Cancel")
            onClicked: {
                password.text = "";
                network.modelData.askingPassword = false;
                network.modelData.errorKind = "";
                network.modelData.errorDetail = "";
            }
        }
        ExButton {
            visible: network.askingPassword
            kind: "accent"
            text: Translation.tr("Connect")
            onClicked: network.submit()
        }
    }

    SettingsHero {
        Layout.fillWidth: true
        on: Network.wifiEnabled
        glyph: Network.wifiEnabled ? "wifi" : "wifi_off"
        text: Network.wifiEnabled ? Translation.tr("Turned on") : Translation.tr("Turned off")
        subtitle: !Network.wifiEnabled ? ""
            : Network.active ? Translation.tr("Connected to %1").arg(Network.active.ssid)
            : Translation.tr("Not connected")
        onSwitched: wanted => Network.enableWifi(wanted)
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Networks")
        visible: Network.wifiEnabled

        SettingsCard {
            glyph: "wifi_find"
            text: Network.wifiScanning ? Translation.tr("Looking for networks...") : Translation.tr("%1 in range").arg(Network.friendlyWifiNetworks.length)

            ExButton {
                kind: "control"
                glyph: "refresh"
                text: Translation.tr("Scan")
                enabled: !Network.wifiScanning
                onClicked: Network.rescanWifi()
            }
        }
        Repeater {
            model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []
            NetworkCard {}
        }
    }
}
