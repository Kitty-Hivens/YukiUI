pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core.services
import qs.core.services.network
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.common

/**
 * One wireless network: what it is, how it is doing, and what can be done with
 * it.
 *
 * The actions open on click rather than sitting on every row: connect, forget
 * and the portal are three buttons per network, and a list of them is unreadable
 * before it is useful. A row that starts asking for a password opens itself,
 * since that question is the whole reason the row is interesting.
 */
ColumnLayout {
    id: root
    required property WifiAccessPoint network
    property bool expanded: false

    readonly property bool isActive: root.network?.active ?? false
    readonly property bool connecting: Network.wifiConnecting && Network.wifiConnectTarget === root.network
    readonly property bool saved: Network.savedNetworks.includes(root.network?.ssid ?? " ")
    readonly property bool askingPassword: root.network?.askingPassword ?? false
    // A network with no security at all, or one NetworkManager reaches but cannot
    // get past, is the shape a captive portal takes.
    readonly property bool needsPortal: root.isActive
        && ((root.network?.security ?? "").trim().length === 0 || Network.wifiStatus === "limited")

    // Same wording as the sidebar's list, deliberately: they are two views of one
    // radio, and a network that says "Wrong password" in one place should not say
    // something else in the other.
    readonly property string statusText: {
        if (root.connecting)
            return Translation.tr("Connecting...");
        if (root.isActive)
            return Network.wifiStatus === "limited" ? Translation.tr("Connected, no internet") : Translation.tr("Connected");
        switch (root.network?.errorKind ?? "") {
        case "wrongPassword":
            return Translation.tr("Wrong password");
        case "secrets":
            return Translation.tr("Password required");
        case "notFound":
            return Translation.tr("Out of range");
        case "timeout":
            return Translation.tr("Connection timed out");
        case "failed":
            return (root.network?.errorDetail ?? "").length > 0 ? root.network.errorDetail : Translation.tr("Could not connect");
        }
        if (root.saved)
            return Translation.tr("Saved");
        return (root.network?.isSecure ?? false) ? Translation.tr("Secured") : Translation.tr("Not secured");
    }
    readonly property bool statusIsError: !root.connecting && !root.isActive
        && (root.network?.errorKind ?? "").length > 0

    // What the row says about the band, once it is open. 2.4 and 5 GHz networks
    // often share a name, and which one is being joined is the difference between
    // reaching across the flat and not.
    readonly property string bandText: {
        const frequency = root.network?.frequency ?? 0;
        if (frequency <= 0)
            return "";
        if (frequency >= 5900)
            return "6 GHz";
        return frequency >= 5000 ? "5 GHz" : "2.4 GHz";
    }

    function submitPassword(): void {
        if (passwordField.text.length === 0)
            return;
        Network.connectToWifiNetwork(root.network, passwordField.text);
        passwordField.clear();
    }

    onAskingPasswordChanged: if (root.askingPassword) {
        root.expanded = true;
        passwordField.forceActiveFocus();
    }

    spacing: 0

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 54
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        onClicked: root.expanded = !root.expanded

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 12

            MaterialSymbol {
                readonly property int strength: root.network?.strength ?? 0
                text: strength > 80 ? "signal_wifi_4_bar"
                    : strength > 60 ? "network_wifi_3_bar"
                    : strength > 40 ? "network_wifi_2_bar"
                    : strength > 20 ? "network_wifi_1_bar"
                    : "signal_wifi_0_bar"
                iconSize: Appearance.font.pixelSize.hugeass
                color: root.isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.network?.ssid ?? Translation.tr("Unknown")
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: root.isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
            }

            MaterialSymbol {
                visible: (root.network?.isSecure ?? false) && !root.isActive
                text: "lock"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.bottomMargin: root.expanded ? 8 : 0
        visible: root.expanded
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                visible: root.bandText.length > 0
                text: root.bandText
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            StyledText {
                visible: (root.network?.security ?? "").length > 0
                text: root.network?.security ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: Translation.tr("Signal: %1%").arg(root.network?.strength ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.askingPassword
            spacing: 8

            MaterialTextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                onAccepted: root.submitPassword()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            DialogButton {
                visible: root.needsPortal
                buttonText: Translation.tr("Open network portal")
                onClicked: Network.openPublicWifiPortal()
            }
            DialogButton {
                visible: root.saved && !root.askingPassword
                buttonText: Translation.tr("Forget")
                // A destructive TEXT button: the label carries the warning and the
                // background only takes a state layer. colErrorHover is 85% of the
                // pure error colour, so using it here put red text on a red fill.
                colText: Appearance.colors.colError
                colBackground: ColorUtils.transparentize(Appearance.colors.colError, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.92)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.88)
                onClicked: Network.forgetWifiNetwork(root.network)
            }
            DialogButton {
                visible: root.askingPassword
                buttonText: Translation.tr("Cancel")
                onClicked: {
                    passwordField.clear();
                    root.network.askingPassword = false;
                    root.network.errorKind = "";
                    root.network.errorDetail = "";
                }
            }
            RippleButtonWithIcon {
                // Held for any attempt in flight, not only this row's: there is one
                // radio, so joining a second network while the first is being joined
                // is not something a row can decide on its own.
                enabled: !Network.wifiConnecting
                materialIcon: root.connecting ? "hourglass" : root.isActive ? "link_off" : "link"
                mainText: root.connecting ? Translation.tr("Connecting...")
                    : root.askingPassword ? Translation.tr("Connect")
                    : root.isActive ? Translation.tr("Disconnect")
                    : Translation.tr("Connect")
                onClicked: {
                    if (root.askingPassword)
                        root.submitPassword();
                    else if (root.isActive)
                        Network.disconnectWifiNetwork();
                    else
                        Network.connectToWifiNetwork(root.network);
                }
            }
        }
    }
}
