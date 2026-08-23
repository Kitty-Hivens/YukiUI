import qs
import qs.core.services
import qs.core.services.network
import qs.core
import qs.common.widgets
import qs.common
import qs.ii
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    RowLayout {
        Layout.fillWidth: true
        // A nested layout fills its parent by default, and this one taking the whole
        // dialog is what pushed the list out of it.
        Layout.fillHeight: false
        spacing: 8

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("Connect to Wi-Fi")
        }

        IconToolbarButton {
            id: rescanButton
            // Sized here rather than by the row: the toolbar button is built to fill
            // the height of a toolbar, and its width follows its height.
            Layout.fillHeight: false
            implicitWidth: 34
            implicitHeight: 34
            text: Network.wifiBackendRestarting ? "restart_alt" : "refresh"
            // Held enabled while a scan runs: a scan that never ends is exactly when
            // the backend restart underneath this button is what is needed.
            enabled: !Network.wifiBackendRestarting

            // Held down, it restarts the daemon the list comes from -- the scan list
            // is only as good as what that daemon answers, and it can stop answering.
            property bool restartedOnHold: false
            downAction: () => {
                rescanButton.restartedOnHold = false;
                holdTimer.restart();
            }
            releaseAction: () => holdTimer.stop()
            onClicked: {
                if (rescanButton.restartedOnHold)
                    return;
                Network.rescanWifi();
            }

            Timer {
                id: holdTimer
                interval: 600
                onTriggered: {
                    rescanButton.restartedOnHold = true;
                    Network.restartWifiBackend();
                }
            }

            StyledToolTip {
                text: Translation.tr("Scan for networks") + "\n" + Translation.tr("Hold to restart %1").arg(Network.wifiBackendUnit)
            }
        }

        StyledSwitch {
            id: wifiSwitch
            checked: Network.wifiStatus !== "disabled"
            // Only a press means the radio should change: reacting to "checked"
            // itself also fires while the dialog is reading the radio's own state.
            // The switch drops its binding when pressed, so it has to be handed back.
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => Network.wifiStatus !== "disabled");
                Network.enableWifi(wanted);
                if (wanted)
                    Network.rescanWifi();
            }
        }
    }
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    // Ways online that are not wifi -- bluetooth tethering, a modem. They carry the
    // connection just as much, so the dialog that lists networks lists them too.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: -15
        Layout.bottomMargin: -15
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        spacing: 0
        visible: Network.otherConnections.length > 0

        Repeater {
            model: Network.otherConnections
            delegate: OtherConnectionItem {
                required property var modelData
                connection: modelData
                Layout.fillWidth: true
            }
        }
    }
    WindowDialogSeparator {
        visible: Network.otherConnections.length > 0
    }
    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        StyledListView {
            anchors.fill: parent
            clip: true
            spacing: 0
            animateAppearance: false

            model: ScriptModel {
                values: Network.friendlyWifiNetworks
            }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                anchors {
                    left: parent?.left
                    right: parent?.right
                }
            }
        }

        // Nothing in the list is three different situations, and a blank panel told
        // them apart for nobody.
        StyledText {
            anchors.centerIn: parent
            width: parent.width - Appearance.rounding.large * 2
            visible: Network.friendlyWifiNetworks.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: {
                if (Network.wifiStatus === "disabled")
                    return Translation.tr("Wi-Fi is off");
                if (Network.wifiScanning)
                    return Translation.tr("Looking for networks...");
                return Translation.tr("No networks found");
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                IiStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
