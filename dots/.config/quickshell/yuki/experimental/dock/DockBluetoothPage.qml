pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.core
import qs.core.services
import qs.experimental.looks

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
                text: Translation.tr("Remove this computer from the device's Bluetooth list if it is still there, then forget the device here and pair it again.")
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
                if (wanted && root.shown)
                    BluetoothStatus.startDiscovery();
            }
        }
    }

    ExProgressLine {
        Layout.fillWidth: true
        running: root.shown && root.discovering
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
                model: BluetoothStatus.unpairedDevices
                DeviceRow {}
            }
            ExText {
                visible: BluetoothStatus.unpairedDevices.length === 0 && root.discovering
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
