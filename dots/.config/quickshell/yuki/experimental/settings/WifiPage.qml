pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// The radio and the networks in range. All of it from Network, the same service
// the shell's own list reads: a second view of one radio, not a second truth.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: ExLooks.spacing.s

    // A network, and under it the password when it asks for one.
    component NetworkCard: ColumnLayout {
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
        spacing: 4

        SettingsCard {
            Layout.fillWidth: true
            glyph: network.strength > 80 ? "signal_wifi_4_bar" : network.strength > 60 ? "network_wifi_3_bar" : network.strength > 40 ? "network_wifi_2_bar" : network.strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
            text: network.modelData?.ssid ?? Translation.tr("Unknown")
            description: [network.status, network.band, (network.modelData?.isSecure ?? false) && !network.active ? (network.modelData?.security ?? "") : ""].filter(part => part.length > 0).join("  ·  ")

            ExButton {
                visible: network.needsPortal
                kind: "flat"
                text: Translation.tr("Open network portal")
                onClicked: Network.openPublicWifiPortal()
            }
            ExButton {
                visible: network.saved && !network.askingPassword
                kind: "flat"
                text: Translation.tr("Forget")
                onClicked: Network.forgetWifiNetwork(network.modelData)
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
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: network.askingPassword
            glyph: "key"
            text: Translation.tr("Password")

            ExTextField {
                id: password
                width: 260
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
                kind: "accent"
                text: Translation.tr("Connect")
                onClicked: network.submit()
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        glyph: Network.wifiEnabled ? "wifi" : "wifi_off"
        text: Translation.tr("Wi-Fi")
        description: !Network.wifiEnabled ? Translation.tr("The radio is off")
            : Network.wifiScanning ? Translation.tr("Looking for networks...")
            : Translation.tr("%1 in range").arg(Network.friendlyWifiNetworks.length)

        ExButton {
            visible: Network.wifiEnabled
            kind: "control"
            glyph: "refresh"
            text: Translation.tr("Scan")
            enabled: !Network.wifiScanning
            onClicked: Network.rescanWifi()
        }
        ExSwitch {
            checked: Network.wifiEnabled
            onToggled: Network.enableWifi(checked)
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Networks")
        visible: Network.wifiEnabled

        Repeater {
            model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []
            NetworkCard {}
        }
        ExText {
            visible: Network.friendlyWifiNetworks.length === 0
            Layout.leftMargin: ExLooks.spacing.l
            text: Network.wifiScanning ? Translation.tr("Looking for networks...") : Translation.tr("Nothing in range")
            dim: true
        }
    }
}
