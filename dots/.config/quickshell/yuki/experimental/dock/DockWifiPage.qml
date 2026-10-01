pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// Wi-Fi in quick settings, as the page Windows opens from the arrow on its
// tile: the radio, the other ways the machine is online, and the networks in
// range. A network opens to what can be done with it, and asks for its
// password in place.
//
// Everything is Network's: the same service the shell's own icons read, so
// this is a second view of one radio, not a second truth.
ColumnLayout {
    id: root

    /** On screen. A scan is asked for each time the page comes up. */
    property bool shown: false
    /** The network opened, by name, or empty. One at a time. */
    property string expandedSsid: ""
    /**
     * The password field being typed into, or null. The dock takes the
     * keyboard while there is one and hands the keys to it.
     */
    property Item keyTarget: null

    signal back
    signal settingsRequested

    onShownChanged: {
        if (root.shown && Network.wifiEnabled)
            Network.rescanWifi();
        if (!root.shown)
            root.expandedSsid = "";
    }

    // Nothing to list is three different situations.
    readonly property bool nothingListed: !Network.wifiEnabled || Network.friendlyWifiNetworks.length === 0
    readonly property string emptyText: !Network.wifiEnabled ? Translation.tr("Wi-Fi is off")
        : Network.wifiScanning ? Translation.tr("Looking for networks...")
        : Translation.tr("No networks found")

    spacing: ExLooks.spacing.s

    function strengthGlyph(strength: int): string {
        return strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar"
            : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar";
    }

    // A network, opened or not.
    component NetworkRow: Rectangle {
        id: row

        required property var modelData
        readonly property string ssid: row.modelData?.ssid ?? ""
        readonly property bool active: row.modelData?.active ?? false
        readonly property bool secure: row.modelData?.isSecure ?? false
        readonly property bool connecting: Network.wifiConnecting && Network.wifiConnectTarget === row.modelData
        readonly property bool saved: Network.savedNetworks.includes(row.ssid)
        readonly property bool askingPassword: row.modelData?.askingPassword ?? false
        readonly property bool expanded: root.expandedSsid === row.ssid && row.ssid.length > 0
        readonly property bool needsPortal: row.active && (!row.secure || Network.wifiStatus === "limited")
        readonly property string errorKind: row.modelData?.errorKind ?? ""
        readonly property bool failed: !row.connecting && !row.active && row.errorKind.length > 0
        readonly property string status: {
            if (row.connecting)
                return Translation.tr("Connecting...");
            if (row.active)
                return Network.wifiStatus === "limited" ? Translation.tr("Connected, no internet") : Translation.tr("Connected");
            switch (row.errorKind) {
            case "wrongPassword":
                return Translation.tr("Wrong password");
            case "secrets":
                return Translation.tr("Password required");
            case "notFound":
                return Translation.tr("Out of range");
            case "timeout":
                return Translation.tr("Connection timed out");
            case "failed":
                return (row.modelData?.errorDetail ?? "").length > 0 ? row.modelData.errorDetail : Translation.tr("Could not connect");
            }
            if (row.saved)
                return Translation.tr("Saved");
            return row.secure ? Translation.tr("Secured") : Translation.tr("Not secured");
        }

        function submit() {
            if (password.text.length === 0)
                return;
            Network.connectToWifiNetwork(row.modelData, password.text);
            password.text = "";
        }

        function cancelPassword() {
            password.text = "";
            if (!row.modelData)
                return;
            row.modelData.askingPassword = false;
            row.modelData.errorKind = "";
            row.modelData.errorDetail = "";
        }

        // The password is asked for once nmcli has said it needs one, which can
        // come after the row was closed again.
        onAskingPasswordChanged: {
            if (row.askingPassword)
                root.expandedSsid = row.ssid;
        }
        readonly property bool typing: row.expanded && row.askingPassword
        onTypingChanged: {
            if (row.typing) {
                root.keyTarget = password.input;
                password.input.forceActiveFocus();
            } else if (root.keyTarget === password.input) {
                root.keyTarget = null;
            }
        }
        Component.onDestruction: {
            if (root.keyTarget === password.input)
                root.keyTarget = null;
        }

        width: parent?.width ?? 0
        implicitHeight: column.implicitHeight + 2 * ExLooks.spacing.s
        radius: ExLooks.radius.control
        color: row.expanded ? ExLooks.colors.surfaceSunken : "transparent"

        Behavior on implicitHeight {
            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: header.containsMouse && !row.expanded
            pressed: header.pressed
        }

        ColumnLayout {
            id: column

            x: ExLooks.spacing.m
            y: ExLooks.spacing.s
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.s

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.m

                Item {
                    implicitWidth: 24
                    implicitHeight: 24

                    ExGlyph {
                        anchors.centerIn: parent
                        text: root.strengthGlyph(row.modelData?.strength ?? 0)
                        fill: row.active ? 1 : 0
                        color: row.active ? ExLooks.colors.accent : ExLooks.colors.text
                    }
                    ExGlyph {
                        visible: row.secure
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -3
                        anchors.bottomMargin: -2
                        text: "lock"
                        fill: 1
                        size: 11
                        color: row.active ? ExLooks.colors.accent : ExLooks.colors.textDim
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: row.ssid
                        textFormat: Text.PlainText
                        role: "label"
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: row.status
                        textFormat: Text.PlainText
                        role: "caption"
                        color: row.failed ? ExLooks.colors.destructive : ExLooks.colors.textDim
                    }
                }
            }

            // What can be done with it.
            RowLayout {
                Layout.fillWidth: true
                visible: row.expanded && !row.askingPassword
                spacing: ExLooks.spacing.s

                Item {
                    Layout.fillWidth: true
                }
                ExButton {
                    visible: row.needsPortal
                    kind: "flat"
                    text: Translation.tr("Sign in")
                    onClicked: Network.openPublicWifiPortal()
                }
                ExButton {
                    visible: row.saved
                    kind: "flat"
                    text: Translation.tr("Forget")
                    enabled: !row.connecting
                    onClicked: Network.forgetWifiNetwork(row.modelData)
                }
                // One radio: while a network is being joined, none of the
                // others can be.
                ExButton {
                    kind: row.active ? "control" : "accent"
                    enabled: !Network.wifiConnecting
                    text: row.connecting ? Translation.tr("Connecting...") : row.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    onClicked: {
                        if (row.active)
                            Network.disconnectWifiNetwork();
                        else
                            Network.connectToWifiNetwork(row.modelData);
                    }
                }
            }

            // The password, asked for in place.
            ColumnLayout {
                Layout.fillWidth: true
                visible: row.typing
                spacing: ExLooks.spacing.s

                ExTextField {
                    id: password

                    property bool reveal: false

                    Layout.fillWidth: true
                    glyph: "key"
                    placeholder: Translation.tr("Network password")
                    input.echoMode: password.reveal ? TextInput.Normal : TextInput.Password
                    input.inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    // Typed into from the dock's window as well as its own, and
                    // only the one holding the keyboard draws a cursor by itself.
                    input.cursorVisible: row.typing
                    input.Keys.onReturnPressed: row.submit()
                    input.Keys.onEnterPressed: row.submit()
                    input.Keys.onEscapePressed: row.cancelPassword()

                    trailing: ExButton {
                        kind: "flat"
                        implicitWidth: 30
                        implicitHeight: 30
                        focusPolicy: Qt.NoFocus
                        glyph: password.reveal ? "visibility_off" : "visibility"
                        onClicked: password.reveal = !password.reveal
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ExLooks.spacing.s

                    Item {
                        Layout.fillWidth: true
                    }
                    ExButton {
                        kind: "control"
                        text: Translation.tr("Cancel")
                        onClicked: row.cancelPassword()
                    }
                    ExButton {
                        kind: "accent"
                        text: Translation.tr("Connect")
                        enabled: password.text.length > 0 && !Network.wifiConnecting
                        onClicked: row.submit()
                    }
                }
            }
        }

        // Opens and closes it. Laid under the controls, which take their own clicks.
        MouseArea {
            id: header

            z: -1
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expandedSsid = row.expanded ? "" : row.ssid
        }
    }

    // A way online that is not Wi-Fi: Bluetooth tethering, a modem. Up and down
    // with a button, nothing more to open.
    component OtherRow: Rectangle {
        id: other

        required property var modelData
        readonly property bool active: other.modelData?.active ?? false
        readonly property bool busy: Network.busyConnectionUuid.length > 0 && Network.busyConnectionUuid === (other.modelData?.uuid ?? "")

        width: parent?.width ?? 0
        implicitHeight: otherRow.implicitHeight + 2 * ExLooks.spacing.s
        radius: ExLooks.radius.control
        color: "transparent"

        RowLayout {
            id: otherRow

            x: ExLooks.spacing.m
            y: ExLooks.spacing.s
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.m

            ExGlyph {
                Layout.preferredWidth: 24
                text: other.modelData?.channel === "cellular" ? "signal_cellular_alt" : "bluetooth"
                fill: other.active ? 1 : 0
                color: other.active ? ExLooks.colors.accent : ExLooks.colors.text
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                ExText {
                    Layout.fillWidth: true
                    text: other.modelData?.name ?? ""
                    textFormat: Text.PlainText
                    role: "label"
                }
                ExText {
                    Layout.fillWidth: true
                    text: other.busy ? (other.active ? Translation.tr("Disconnecting...") : Translation.tr("Connecting..."))
                        : other.active ? Translation.tr("Connected") : Translation.tr("Saved")
                    role: "caption"
                    dim: true
                }
            }
            ExButton {
                kind: other.active ? "control" : "tonal"
                enabled: !Network.connectionBusy
                text: other.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (other.active)
                        Network.deactivateConnection(other.modelData.uuid);
                    else
                        Network.activateConnection(other.modelData.uuid);
                }
            }
        }
    }

    // Back, the name of the page, a fresh scan and the radio.
    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.xs

        ExButton {
            kind: "flat"
            glyph: "arrow_back"
            onClicked: root.back()
        }
        ExText {
            Layout.fillWidth: true
            Layout.leftMargin: ExLooks.spacing.xs
            text: Translation.tr("Wi-Fi")
            role: "title"
        }
        ExButton {
            visible: Network.wifiEnabled
            kind: "flat"
            glyph: "refresh"
            enabled: !Network.wifiScanning
            onClicked: Network.rescanWifi()
        }
        ExSwitch {
            Layout.leftMargin: ExLooks.spacing.xs
            Layout.rightMargin: ExLooks.spacing.xs
            checked: Network.wifiEnabled
            onToggled: {
                const wanted = checked;
                // The radio answers for itself: the switch goes back to
                // following it, and moves once the radio has.
                checked = Qt.binding(() => Network.wifiEnabled);
                Network.enableWifi(wanted);
            }
        }
    }

    ExProgressLine {
        Layout.fillWidth: true
        running: root.shown && Network.wifiScanning
    }

    Flickable {
        id: scroller

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: lists.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: lists

            width: scroller.width
            spacing: 2

            ExText {
                visible: Network.otherConnections.length > 0
                leftPadding: ExLooks.spacing.m
                topPadding: ExLooks.spacing.xs
                bottomPadding: ExLooks.spacing.xs
                text: Translation.tr("Other connections")
                role: "caption"
                dim: true
            }
            Repeater {
                model: Network.otherConnections
                OtherRow {}
            }
            ExText {
                visible: Network.otherConnections.length > 0 && Network.wifiEnabled
                leftPadding: ExLooks.spacing.m
                topPadding: ExLooks.spacing.s
                bottomPadding: ExLooks.spacing.xs
                text: Translation.tr("Wi-Fi networks")
                role: "caption"
                dim: true
            }
            Repeater {
                model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []
                NetworkRow {}
            }
            // Under the other connections when there are some.
            ExText {
                visible: root.nothingListed && Network.otherConnections.length > 0
                leftPadding: ExLooks.spacing.m
                topPadding: ExLooks.spacing.s
                text: root.emptyText
                dim: true
            }
        }

        // In the middle when nothing else is listed.
        ExText {
            anchors.centerIn: parent
            width: parent.width - 2 * ExLooks.spacing.l
            visible: root.nothingListed && Network.otherConnections.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            dim: true
            text: root.emptyText
        }
    }

    ExButton {
        Layout.alignment: Qt.AlignLeft
        kind: "flat"
        text: Translation.tr("More Wi-Fi settings")
        onClicked: root.settingsRequested()
    }
}
