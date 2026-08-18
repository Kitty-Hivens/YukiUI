import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.core.services
import qs.core.services.network
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks
import qs.waffle.actionCenter

Item {
    id: root

    Component.onCompleted: {
        Network.rescanWifi();
    }

    WPanelPageColumn {
        anchors.fill: parent

        BodyRectangle {
            implicitHeight: Looks.sizes.controlPageHeight
            implicitWidth: 50

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                ColumnLayout {
                    implicitHeight: headerRow.implicitHeight
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        HeaderRow {
                            id: headerRow
                            Layout.fillWidth: true
                            title: Translation.tr("Wi-Fi")
                        }
                        WSwitch {
                            id: toggleSwitch
                            Layout.rightMargin: 12
                            checked: Network.wifiStatus !== "disabled"
                            // Only a press means the radio should change: reacting to "checked"
                            // itself also fired while the panel was reading the radio's own
                            // state. The switch drops its binding when pressed, so the state
                            // has to be handed back to it.
                            onToggled: {
                                const wanted = checked;
                                checked = Qt.binding(() => Network.wifiStatus !== "disabled");
                                Network.enableWifi(wanted);
                                if (wanted)
                                    Network.rescanWifi();
                            }
                        }
                    }
                    FadeLoader {
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                        Layout.fillWidth: true
                        shown: Network.wifiScanning
                        visible: true
                        sourceComponent: WIndeterminateProgressBar {}
                    }
                }

                StyledListView {
                    // Kept for its animations; the scrollbar is ours.
                    scrollBar: WScrollBar {}
                    id: listView
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    animateAppearance: false

                    clip: true
                    spacing: 4

                    model: ScriptModel {
                        values: Network.friendlyWifiNetworks
                    }
                    delegate: WWifiNetworkItem {
                        required property WifiAccessPoint modelData
                        wifiNetwork: modelData
                        width: ListView.view.width
                    }
                }
            }
        }

        WPanelSeparator {}

        FooterRectangle {
            WTextButton {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                }
                text: Translation.tr("More Internet settings")
                onClicked: {
                    GlobalStates.sidebarLeftOpen = false;
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.network]);
                }
            }
            WBorderlessButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                enabled: !Network.wifiScanning

                onClicked: {
                    Network.rescanWifi();
                }

                contentItem: FluentIcon {
                    icon: "arrow-counterclockwise"
                }
            }
        }
    }
}
