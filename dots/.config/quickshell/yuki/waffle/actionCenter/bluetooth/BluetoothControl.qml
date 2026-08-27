import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth
import qs
import qs.core.services
import qs.core.services.network
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks
import qs.waffle.actionCenter
import qs.waffle

Item {
    id: root

    Component.onCompleted: {
        if (Bluetooth.defaultAdapter?.enabled)
            Bluetooth.defaultAdapter.discovering = true;
    }
    Component.onDestruction: {
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = false;
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
                            title: Translation.tr("Bluetooth")
                        }
                        WSwitch {
                            id: toggleSwitch
                            Layout.rightMargin: 12
                            checked: Bluetooth.defaultAdapter?.enabled ?? false
                            // Only a press means the adapter should change: reacting to
                            // "checked" itself also fired while the panel was reading the
                            // adapter's own state. The switch drops its binding when pressed,
                            // so the state has to be handed back to it.
                            onToggled: {
                                const wanted = checked;
                                checked = Qt.binding(() => Bluetooth.defaultAdapter?.enabled ?? false);
                                const adapter = Bluetooth.defaultAdapter;
                                if (!adapter)
                                    return;
                                adapter.enabled = wanted;
                                adapter.discovering = wanted;
                            }
                        }
                    }
                    FadeLoader {
                        Layout.leftMargin: -4
                        Layout.rightMargin: -4
                        Layout.fillWidth: true
                        shown: Bluetooth.defaultAdapter?.discovering ?? false
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
                        values: BluetoothStatus.friendlyDeviceList
                    }
                    delegate: BluetoothDeviceItem {
                        required property BluetoothDevice modelData
                        device: modelData
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
                text: Translation.tr("More Bluetooth settings")
                onClicked: {
                    WStates.sidebarLeftOpen = false;
                    Session.openSystemSettings("bluetooth", Config.options.apps.bluetooth);
                }
            }
            WBorderlessButton {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 12
                enabled: !Bluetooth.defaultAdapter?.discovering && Bluetooth.defaultAdapter?.enabled

                onClicked: {
                    Bluetooth.defaultAdapter.discovering = true;
                }

                contentItem: FluentIcon {
                    icon: "arrow-counterclockwise"
                }
            }
        }
    }
}
