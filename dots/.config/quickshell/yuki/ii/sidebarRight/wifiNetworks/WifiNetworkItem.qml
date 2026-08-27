import qs
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.core.services
import qs.core.services.network
import qs.common
import qs.ii
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property WifiAccessPoint wifiNetwork
    property bool expanded: false

    readonly property bool isActive: root.wifiNetwork?.active ?? false
    readonly property bool connecting: Network.wifiConnecting && Network.wifiConnectTarget === root.wifiNetwork
    readonly property bool saved: Network.savedNetworks.includes(root.wifiNetwork?.ssid ?? " ")
    readonly property bool askingPassword: root.wifiNetwork?.askingPassword ?? false
    // A network with no security at all, or one NetworkManager can reach but not get
    // past, is the shape a captive portal takes.
    readonly property bool needsPortal: root.isActive
        && ((root.wifiNetwork?.security ?? "").trim().length === 0 || Network.wifiStatus === "limited")

    active: root.isActive || root.askingPassword
    pointingHandCursor: !root.expanded
    // Opens the network rather than joining it. A single click used to connect, so
    // clicking the one already connected made the shell drop it and join it again.
    onClicked: root.expanded = !root.expanded
    altAction: () => root.expanded = !root.expanded

    onAskingPasswordChanged: if (root.askingPassword) {
        root.expanded = true;
        passwordField.forceActiveFocus();
    }

    readonly property string statusText: {
        if (root.connecting)
            return Translation.tr("Connecting...");
        if (root.isActive)
            return Network.wifiStatus === "limited" ? Translation.tr("Connected, no internet") : Translation.tr("Connected");
        switch (root.wifiNetwork?.errorKind ?? "") {
        case "wrongPassword":
            return Translation.tr("Wrong password");
        case "secrets":
            return Translation.tr("Password required");
        case "notFound":
            return Translation.tr("Out of range");
        case "timeout":
            return Translation.tr("Connection timed out");
        case "failed":
            return (root.wifiNetwork?.errorDetail ?? "").length > 0 ? root.wifiNetwork.errorDetail : Translation.tr("Could not connect");
        }
        if (root.saved)
            return Translation.tr("Saved");
        return (root.wifiNetwork?.isSecure ?? false) ? Translation.tr("Secured") : Translation.tr("Not secured");
    }
    readonly property bool statusIsError: !root.connecting && !root.isActive
        && (root.wifiNetwork?.errorKind ?? "").length > 0

    function submitPassword(): void {
        if (passwordField.text.length === 0)
            return;
        Network.connectToWifiNetwork(root.wifiNetwork, passwordField.text);
        passwordField.clear();
    }

    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnPrimary
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout { // Name
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                property int strength: root.wifiNetwork?.strength ?? 0
                text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
                    textFormat: Text.PlainText
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: root.statusText
                    textFormat: Text.PlainText
                }
            }

            MaterialSymbol {
                visible: (root.wifiNetwork?.isSecure ?? false) && !root.isActive
                text: "lock"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                visible: root.isActive
                text: "check"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        ColumnLayout { // Password
            id: passwordPrompt
            Layout.topMargin: 8
            visible: root.expanded && root.askingPassword

            MaterialTextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")

                // Password
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData

                onAccepted: root.submitPassword()
            }

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: {
                        passwordField.clear();
                        root.wifiNetwork.askingPassword = false;
                        root.wifiNetwork.errorKind = "";
                        root.wifiNetwork.errorDetail = "";
                    }
                }

                ActionButton {
                    buttonText: Translation.tr("Connect")
                    // Held for any attempt in flight, not only this row's: there is
                    // one radio, so joining a second network while the first is
                    // being joined is not something the row can do on its own.
                    enabled: !Network.wifiConnecting
                    onClicked: root.submitPassword()
                }
            }
        }

        RowLayout { // Actions
            Layout.topMargin: 8
            visible: root.expanded && !root.askingPassword

            Item {
                Layout.fillWidth: true
            }

            DialogButton {
                visible: root.needsPortal
                buttonText: Translation.tr("Open network portal")
                onClicked: {
                    Network.openPublicWifiPortal();
                    IiStates.sidebarRightOpen = false;
                }
            }

            DialogButton {
                visible: root.saved
                buttonText: Translation.tr("Forget")
                // A destructive TEXT button: the label carries the warning and the
                // background only takes a state layer. colErrorHover is 85% of the
                // pure error colour, so using it here put red text on a red fill.
                colText: Appearance.colors.colError
                colBackground: ColorUtils.transparentize(Appearance.colors.colError, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.92)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.88)
                onClicked: Network.forgetWifiNetwork(root.wifiNetwork)
            }

            ActionButton {
                enabled: !Network.wifiConnecting
                buttonText: root.connecting ? Translation.tr("Connecting...") : root.isActive ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (root.isActive)
                        Network.disconnectWifiNetwork();
                    else
                        Network.connectToWifiNetwork(root.wifiNetwork);
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
