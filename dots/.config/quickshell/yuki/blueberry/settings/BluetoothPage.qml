pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.core
import qs.core.services
import qs.blueberry.looks

// The adapter, what is connected, what is remembered and what is nearby: three
// lists rather than one sorted by state, which would read as one list shuffling
// under the pointer. Pairing asks for its code through the shell's own agent.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    // What answers with nothing but its address: watches, tags, a
    // neighbour's television, advertising beacons. Most of what a scan finds
    // on Linux looks like that, and it buried the devices worth pairing, so
    // it is left out unless asked for, as Windows does.
    property bool showUnnamed: false
    function named(device): bool {
        const name = device?.name ?? "";
        return name.length > 0 && !/^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/.test(name);
    }
    readonly property var nearby: root.showUnnamed ? BluetoothStatus.unpairedDevices : BluetoothStatus.unpairedDevices.filter(device => root.named(device))
    readonly property int unnamedCount: BluetoothStatus.unpairedDevices.length - BluetoothStatus.unpairedDevices.filter(device => root.named(device)).length

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool discovering: root.adapter?.discovering ?? false

    function toggleSearch() {
        if (root.discovering)
            BluetoothStatus.stopDiscovery();
        else
            BluetoothStatus.startDiscovery();
    }

    // Left running, discovery keeps the radio busy for a window nobody is
    // looking at.
    Component.onDestruction: {
        if (root.discovering)
            BluetoothStatus.stopDiscovery();
    }

    spacing: ExLooks.spacing.s

    component DeviceCard: SettingsCard {
        id: device

        required property var modelData
        readonly property bool connected: device.modelData?.connected ?? false
        readonly property bool paired: device.modelData?.paired ?? false
        readonly property bool busy: device.modelData?.state === BluetoothDeviceState.Connecting || device.modelData?.state === BluetoothDeviceState.Disconnecting
            || (BluetoothStatus.connectingAddresses[device.modelData?.address ?? ""] ?? false)
        readonly property string failure: device.connected ? "" : (BluetoothStatus.connectFailures[device.modelData?.address ?? ""] ?? "")

        Layout.fillWidth: true
        glyph: Icons.getBluetoothDeviceMaterialSymbol(device.modelData?.icon || "")
        text: device.modelData?.name || Translation.tr("Unknown device")
        description: {
            if (device.busy)
                return device.connected ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
            switch (device.failure) {
            case "keyMissing":
                return Translation.tr("The device no longer knows this computer. The pairing has to be made anew.");
            case "unreachable":
                return Translation.tr("Out of range or switched off");
            case "refused":
                return Translation.tr("The device refused the connection");
            case "failed":
                return Translation.tr("Could not connect: %1").arg(BluetoothStatus.connectFailureDetails[device.modelData?.address ?? ""] || Translation.tr("no reason given"));
            }
            if (!device.paired)
                return device.modelData?.address ?? "";
            const base = device.connected ? Translation.tr("Connected") : Translation.tr("Paired");
            return device.connected && device.modelData?.batteryAvailable ? `${base}  ·  ${Math.round(device.modelData.battery * 100)}%` : base;
        }

        ExButton {
            visible: device.paired
            kind: "flat"
            text: Translation.tr("Forget")
            onClicked: device.modelData?.forget()
        }
        ExButton {
            visible: device.failure === "keyMissing"
            kind: "accent"
            enabled: !device.busy && BluetoothStatus.repairState !== "searching" && BluetoothStatus.repairState !== "pairing"
            text: Translation.tr("Pair again")
            onClicked: BluetoothStatus.repair(device.modelData)
        }
        ExButton {
            visible: device.failure !== "keyMissing"
            kind: device.connected ? "control" : "tonal"
            enabled: !device.busy
            text: device.connected ? Translation.tr("Disconnect") : device.paired ? Translation.tr("Connect") : Translation.tr("Pair")
            onClicked: {
                if (device.connected)
                    device.modelData?.disconnect();
                else if (device.paired)
                    BluetoothStatus.connectDevice(device.modelData);
                else
                    BluetoothStatus.pair(device.modelData);
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        glyph: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        text: Translation.tr("Bluetooth")
        description: !BluetoothStatus.available ? Translation.tr("No bluetooth adapter")
            : !BluetoothStatus.enabled ? Translation.tr("Off")
            : root.discovering ? Translation.tr("Looking for devices...")
            : BluetoothStatus.activeDeviceCount > 0 ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
            : Translation.tr("On, nothing connected")

        ExButton {
            visible: BluetoothStatus.enabled
            kind: "control"
            glyph: root.discovering ? "stop" : "search"
            text: root.discovering ? Translation.tr("Stop") : Translation.tr("Add device")
            onClicked: root.toggleSearch()
        }
        ExSwitch {
            enabled: BluetoothStatus.available
            checked: BluetoothStatus.enabled
            onToggled: {
                if (root.adapter)
                    root.adapter.enabled = checked;
            }
        }
    }

    // A pairing being made anew. The device leaves the lists with its old
    // pairing, so how it is going is said here.
    SettingsCard {
        Layout.fillWidth: true
        visible: BluetoothStatus.repairState.length > 0
        glyph: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound" ? "error" : "bluetooth_searching"
        text: BluetoothStatus.repairName
        description: {
            switch (BluetoothStatus.repairState) {
            case "searching":
                return Translation.tr("Looking for it. Open Bluetooth on it so it can be found.");
            case "pairing":
                return Translation.tr("Pairing. Compare the code on both screens.");
            case "notFound":
                return Translation.tr("Not found. Open Bluetooth on it and try again.");
            case "failed":
                return Translation.tr("Pairing did not go through.");
            }
            return "";
        }

        ExButton {
            visible: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound"
            kind: "tonal"
            text: Translation.tr("Try again")
            onClicked: BluetoothStatus.retryRepair()
        }
        ExButton {
            visible: BluetoothStatus.repairState !== "pairing"
            kind: "control"
            text: Translation.tr("Cancel")
            onClicked: BluetoothStatus.cancelRepair()
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Connected")
        visible: BluetoothStatus.connectedDevices.length > 0

        Repeater {
            model: BluetoothStatus.connectedDevices
            DeviceCard {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Remembered")
        visible: BluetoothStatus.pairedButNotConnectedDevices.length > 0

        Repeater {
            model: BluetoothStatus.pairedButNotConnectedDevices
            DeviceCard {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Nearby")
        visible: BluetoothStatus.enabled && (root.discovering || BluetoothStatus.unpairedDevices.length > 0)

        Repeater {
            model: root.nearby
            DeviceCard {}
        }
        ExButton {
            visible: root.unnamedCount > 0
            kind: "flat"
            text: root.showUnnamed ? Translation.tr("Hide devices without a name") : Translation.tr("Show devices without a name (%1)").arg(root.unnamedCount)
            onClicked: root.showUnnamed = !root.showUnnamed
        }
        ExText {
            visible: root.nearby.length === 0
            Layout.leftMargin: ExLooks.spacing.l
            text: Translation.tr("Turn the device on and put it into pairing mode")
            dim: true
        }
    }
}
