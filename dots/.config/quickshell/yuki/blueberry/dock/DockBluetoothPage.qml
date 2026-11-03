pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.core
import qs.core.services
import qs.blueberry.looks

// Bluetooth in quick settings: the adapter, what is connected, what is
// remembered, and while the page is up, what is nearby. A device opens to what
// can be done with it. Pairing asks for its code through the shell's own agent.
ColumnLayout {
    id: root

    /** On screen. Nearby devices are looked for only while it is. */
    property bool shown: false
    /** The device opened, by address, or empty. One at a time. */
    property string expandedAddress: ""

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool discovering: root.adapter?.discovering ?? false

    signal back
    signal settingsRequested

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

    // Left running, discovery keeps the radio busy with nobody looking. The
    // service holds the stop back while a pairing started here still rides on
    // the scan.
    onShownChanged: {
        if (root.shown && BluetoothStatus.enabled)
            BluetoothStatus.startDiscovery();
        else if (!root.shown) {
            root.expandedAddress = "";
            if (root.discovering)
                BluetoothStatus.stopDiscovery();
        }
    }
    Component.onDestruction: {
        if (root.discovering)
            BluetoothStatus.stopDiscovery();
    }
    // Turned on from here, the scan starts once the adapter is up. Asked for
    // straight after asking it to power on, BlueZ answered that it was not
    // ready, and nothing was found until the page was opened again.
    Connections {
        target: BluetoothStatus
        function onEnabledChanged() {
            if (BluetoothStatus.enabled && root.shown)
                BluetoothStatus.startDiscovery();
        }
    }

    spacing: ExLooks.spacing.s

    component DeviceRow: Rectangle {
        id: row

        required property var modelData
        readonly property string address: row.modelData?.address ?? ""
        readonly property bool connected: row.modelData?.connected ?? false
        readonly property bool paired: row.modelData?.paired ?? false
        readonly property bool pairing: (row.modelData?.pairing ?? false) || BluetoothStatus.pairingDevice === row.modelData
        readonly property bool busy: row.modelData?.state === BluetoothDeviceState.Connecting || row.modelData?.state === BluetoothDeviceState.Disconnecting
            || (BluetoothStatus.connectingAddresses[row.address] ?? false)
        readonly property bool expanded: root.expandedAddress === row.address && row.address.length > 0
        readonly property string failure: row.connected ? "" : (BluetoothStatus.connectFailures[row.address] ?? "")
        readonly property string status: {
            if (row.pairing)
                return Translation.tr("Pairing...");
            if (row.busy)
                return row.connected ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
            switch (row.failure) {
            case "keyMissing":
                return Translation.tr("The device no longer knows this computer");
            case "unreachable":
                return Translation.tr("Out of range or switched off");
            case "refused":
                return Translation.tr("The device refused the connection");
            case "failed":
                return Translation.tr("Could not connect: %1").arg(BluetoothStatus.connectFailureDetails[row.address] || Translation.tr("no reason given"));
            }
            if (row.connected)
                return row.modelData?.batteryAvailable ? `${Translation.tr("Connected")}  ·  ${Math.round(row.modelData.battery * 100)}%` : Translation.tr("Connected");
            if (row.paired)
                return Translation.tr("Paired");
            return Translation.tr("Not paired");
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

                ExGlyph {
                    Layout.preferredWidth: 24
                    text: Icons.getBluetoothDeviceMaterialSymbol(row.modelData?.icon || "")
                    fill: row.connected ? 1 : 0
                    color: row.connected ? ExLooks.colors.accent : ExLooks.colors.text
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: row.modelData?.name || Translation.tr("Unknown device")
                        textFormat: Text.PlainText
                        role: "label"
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: row.status
                        role: "caption"
                        color: row.failure.length > 0 && !row.busy ? ExLooks.colors.destructive : ExLooks.colors.textDim
                    }
                }
            }

            // A pairing the device has dropped on its side cannot be connected
            // again, only made anew.
            ExText {
                Layout.fillWidth: true
                visible: row.expanded && row.failure === "keyMissing" && !row.busy
                text: Translation.tr("The pairing has to be made anew. Open Bluetooth on the device so it can be found, and compare the code on both screens.")
                wrapMode: Text.Wrap
                role: "caption"
                dim: true
            }

            RowLayout {
                Layout.fillWidth: true
                visible: row.expanded
                spacing: ExLooks.spacing.s

                Item {
                    Layout.fillWidth: true
                }
                ExButton {
                    visible: row.paired
                    kind: "flat"
                    text: Translation.tr("Forget")
                    enabled: !row.busy
                    onClicked: {
                        root.expandedAddress = "";
                        row.modelData?.forget();
                    }
                }
                ExButton {
                    visible: row.failure === "keyMissing"
                    kind: "accent"
                    enabled: !row.busy && BluetoothStatus.repairState !== "searching" && BluetoothStatus.repairState !== "pairing"
                    text: Translation.tr("Pair again")
                    onClicked: {
                        root.expandedAddress = "";
                        BluetoothStatus.repair(row.modelData);
                    }
                }
                ExButton {
                    visible: row.failure !== "keyMissing"
                    kind: row.connected ? "control" : "accent"
                    enabled: !row.busy && !row.pairing
                    text: row.connected ? Translation.tr("Disconnect") : row.paired ? Translation.tr("Connect") : Translation.tr("Pair")
                    onClicked: {
                        if (row.connected)
                            row.modelData?.disconnect();
                        else if (row.paired)
                            BluetoothStatus.connectDevice(row.modelData);
                        else
                            BluetoothStatus.pair(row.modelData);
                    }
                }
            }
        }

        MouseArea {
            id: header

            z: -1
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expandedAddress = row.expanded ? "" : row.address
        }
    }

    component SectionLabel: ExText {
        leftPadding: ExLooks.spacing.m
        topPadding: ExLooks.spacing.s
        bottomPadding: ExLooks.spacing.xs
        role: "caption"
        dim: true
    }

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
            text: Translation.tr("Bluetooth")
            role: "title"
        }
        ExSwitch {
            Layout.leftMargin: ExLooks.spacing.xs
            Layout.rightMargin: ExLooks.spacing.xs
            enabled: BluetoothStatus.available
            checked: BluetoothStatus.enabled
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => BluetoothStatus.enabled);
                if (!root.adapter)
                    return;
                root.adapter.enabled = wanted;
            }
        }
    }

    ExProgressLine {
        Layout.fillWidth: true
        running: root.shown && root.discovering
    }

    // A pairing being made anew. The device's row goes the moment the old
    // pairing does, so how it is going is said here.
    Rectangle {
        Layout.fillWidth: true
        visible: BluetoothStatus.repairState.length > 0
        implicitHeight: repairRow.implicitHeight + 2 * ExLooks.spacing.s
        radius: ExLooks.radius.control
        color: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound" ? ExLooks.colors.surfaceSunken : ExLooks.colors.tonal

        readonly property color ink: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound" ? ExLooks.colors.text : ExLooks.colors.tonalInk

        RowLayout {
            id: repairRow

            x: ExLooks.spacing.m
            y: ExLooks.spacing.s
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.m

            ExGlyph {
                text: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound" ? "error" : "bluetooth_searching"
                color: parent.parent.ink
            }
            ExText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                role: "caption"
                color: parent.parent.ink
                text: {
                    const name = BluetoothStatus.repairName;
                    switch (BluetoothStatus.repairState) {
                    case "searching":
                        return Translation.tr("Looking for %1. Open Bluetooth on it so it can be found.").arg(name);
                    case "pairing":
                        return Translation.tr("Pairing with %1. Compare the code on both screens.").arg(name);
                    case "notFound":
                        return Translation.tr("%1 was not found. Open Bluetooth on it and try again.").arg(name);
                    case "failed":
                        return Translation.tr("Pairing with %1 did not go through.").arg(name);
                    }
                    return "";
                }
            }
            ExButton {
                visible: BluetoothStatus.repairState === "failed" || BluetoothStatus.repairState === "notFound"
                kind: "tonal"
                text: Translation.tr("Try again")
                onClicked: BluetoothStatus.retryRepair()
            }
            ExButton {
                visible: BluetoothStatus.repairState !== "pairing"
                kind: "flat"
                glyph: "close"
                onClicked: BluetoothStatus.cancelRepair()
            }
        }
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

        // Three lists rather than one sorted by state, which would read as one
        // list shuffling under the pointer.
        Column {
            id: lists

            width: scroller.width
            spacing: 2
            visible: BluetoothStatus.enabled

            SectionLabel {
                visible: BluetoothStatus.connectedDevices.length > 0
                topPadding: ExLooks.spacing.xs
                text: Translation.tr("Connected")
            }
            Repeater {
                model: BluetoothStatus.connectedDevices
                DeviceRow {}
            }
            SectionLabel {
                visible: BluetoothStatus.pairedButNotConnectedDevices.length > 0
                text: Translation.tr("Remembered")
            }
            Repeater {
                model: BluetoothStatus.pairedButNotConnectedDevices
                DeviceRow {}
            }
            SectionLabel {
                visible: BluetoothStatus.unpairedDevices.length > 0 || root.discovering
                text: Translation.tr("Nearby")
            }
            Repeater {
                model: root.nearby
                DeviceRow {}
            }
            ExButton {
                visible: root.unnamedCount > 0
                x: ExLooks.spacing.xs
                kind: "flat"
                text: root.showUnnamed ? Translation.tr("Hide devices without a name") : Translation.tr("Show devices without a name (%1)").arg(root.unnamedCount)
                onClicked: root.showUnnamed = !root.showUnnamed
            }
            ExText {
                visible: root.nearby.length === 0 && root.discovering
                leftPadding: ExLooks.spacing.m
                rightPadding: ExLooks.spacing.m
                width: lists.width
                wrapMode: Text.Wrap
                text: Translation.tr("Turn the device on and put it into pairing mode")
                role: "caption"
                dim: true
            }
        }

        ExText {
            anchors.centerIn: parent
            width: parent.width - 2 * ExLooks.spacing.l
            visible: !BluetoothStatus.enabled
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            dim: true
            text: !BluetoothStatus.available ? Translation.tr("No Bluetooth adapter") : Translation.tr("Bluetooth is off")
        }
    }

    ExButton {
        Layout.alignment: Qt.AlignLeft
        kind: "flat"
        text: Translation.tr("More Bluetooth settings")
        onClicked: root.settingsRequested()
    }
}
