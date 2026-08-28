pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.core.services
import qs.core
import qs.ii.systemSettings
import qs.ii.looks
import qs.common.widgets
import qs.common

/**
 * The adapter, what is connected to it, what it remembers, and what it can see.
 *
 * Three lists rather than one, because the three answer different questions: in
 * use now, known and idle, and nearby but a stranger. A single list sorted by
 * state reads as one thing changing places under the pointer.
 */
Item {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: BluetoothStatus.available
    readonly property bool enabled: BluetoothStatus.enabled
    readonly property bool discovering: root.adapter?.discovering ?? false
    readonly property int knownCount: BluetoothStatus.connectedDevices.length + BluetoothStatus.pairedButNotConnectedDevices.length
    readonly property bool empty: root.knownCount === 0 && BluetoothStatus.unpairedDevices.length === 0

    // Discovery is stopped on the way out. Left running it keeps the radio busy
    // and the battery draining for a window nobody is looking at any more --
    // but not while a pairing is still riding on the scan.
    Component.onDestruction: {
        if (root.adapter?.discovering)
            BluetoothStatus.stopDiscovery();
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                id: adapterCard
                Layout.fillWidth: true
                icon: root.enabled ? "bluetooth" : "bluetooth_disabled"
                title: !root.available ? Translation.tr("No bluetooth adapter")
                    : root.enabled ? (BluetoothStatus.activeDeviceCount > 0
                        ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
                        : Translation.tr("On, nothing connected"))
                    : Translation.tr("Off")
                subtitle: root.adapter?.name ?? ""

                ConfigSwitch {
                    id: adapterSwitch
                    text: Translation.tr("Bluetooth")
                    buttonIcon: "bluetooth"
                    enabled: root.available
                    // Restated through Binding: the control writes its own property
                    // when touched, which drops the binding and leaves it showing
                    // what was asked for rather than what the adapter did.
                    Binding {
                        target: adapterSwitch
                        property: "checked"
                        value: root.enabled
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (root.adapter && checked !== root.adapter.enabled)
                            root.adapter.enabled = checked;
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    // While the page is empty the search lives in the middle of it,
                    // where the eye already is. Two buttons for one action is one
                    // button too many.
                    visible: !(root.enabled && root.empty)

                    StyledText {
                        Layout.fillWidth: true
                        text: !root.available ? Translation.tr("Nothing here has bluetooth")
                            : !root.enabled ? Translation.tr("The radio is off")
                            : root.discovering ? Translation.tr("Looking for devices...")
                            : root.knownCount > 0 ? Translation.tr("%1 remembered").arg(root.knownCount)
                            : ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                    RippleButtonWithIcon {
                        enabled: root.enabled
                        materialIcon: root.discovering ? "stop" : "search"
                        mainText: root.discovering ? Translation.tr("Stop") : Translation.tr("Search")
                        onClicked: {
                            if (root.discovering)
                                BluetoothStatus.stopDiscovery();
                            else
                                BluetoothStatus.startDiscovery();
                        }
                    }
                }

                // Not a bar: there is nothing to measure while the radio looks
                // around, and an indeterminate bar borrows the shape of progress
                // for something that has none.
                MarkTrail {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    visible: root.discovering
                    running: root.discovering
                }
            }

            PageHeading {
                visible: BluetoothStatus.connectedDevices.length > 0
                text: Translation.tr("Connected")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: BluetoothStatus.connectedDevices.length > 0

                Repeater {
                    model: BluetoothStatus.connectedDevices

                    delegate: ColumnLayout {
                        id: connectedEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: connectedEntry.index > 0
                        }
                        BluetoothDeviceRow {
                            Layout.fillWidth: true
                            device: connectedEntry.modelData
                        }
                    }
                }
            }

            PageHeading {
                visible: BluetoothStatus.pairedButNotConnectedDevices.length > 0
                text: Translation.tr("Remembered")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: BluetoothStatus.pairedButNotConnectedDevices.length > 0

                Repeater {
                    model: BluetoothStatus.pairedButNotConnectedDevices

                    delegate: ColumnLayout {
                        id: pairedEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: pairedEntry.index > 0
                        }
                        BluetoothDeviceRow {
                            Layout.fillWidth: true
                            device: pairedEntry.modelData
                        }
                    }
                }
            }

            // Nothing known, nothing in range: the page has one thing to say and
            // one thing to offer, so it says it in the middle instead of leaving
            // three empty headings above a blank half-screen.
            PageEmpty {
                visible: root.enabled && root.empty
                roomLeft: pageFlick.height - adapterCard.implicitHeight - 72
                symbol: root.discovering ? "bluetooth_searching" : "bluetooth_disabled"
                heading: root.discovering ? Translation.tr("Looking for devices...") : Translation.tr("No devices yet")
                message: Translation.tr("Turn the device on, put it into pairing mode, and search for it")
                actionIcon: root.discovering ? "stop" : "search"
                actionText: root.discovering ? Translation.tr("Stop") : Translation.tr("Search")
                onActionClicked: {
                    if (root.discovering)
                        BluetoothStatus.stopDiscovery();
                    else
                        BluetoothStatus.startDiscovery();
                }
            }

            PageHeading {
                visible: root.enabled && BluetoothStatus.unpairedDevices.length > 0
                text: Translation.tr("Nearby")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: root.enabled && BluetoothStatus.unpairedDevices.length > 0

                Repeater {
                    model: BluetoothStatus.unpairedDevices

                    delegate: ColumnLayout {
                        id: nearbyEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: nearbyEntry.index > 0
                        }
                        BluetoothDeviceRow {
                            Layout.fillWidth: true
                            device: nearbyEntry.modelData
                        }
                    }
                }
            }
        }
    }
}
