pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    /**
     * The device this shell asked to pair and has not heard back about.
     *
     * Discovery has to outlive the surface that started it. The pairing prompt
     * takes focus, which clears the panel's focus grab, which closes the panel
     * -- and the panel's own teardown then stops the scan, in the middle of the
     * pairing that panel just started. A device BlueZ knows only from a scan can
     * go with the scan, and the pairing goes with the device.
     */
    property BluetoothDevice pairingDevice: null
    readonly property bool pairing: root.pairingDevice !== null
    /** A stop that was asked for while a pairing was still riding on the scan. */
    property bool stopWhenSettled: false

    function pair(device) {
        if (!device)
            return;
        root.pairingDevice = device;
        pairingTimeout.restart();
        device.pair();
    }

    function startDiscovery() {
        root.stopWhenSettled = false;
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = true;
    }

    function stopDiscovery() {
        if (root.pairing) {
            root.stopWhenSettled = true;
            return;
        }
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = false;
    }

    function settlePairing() {
        root.pairingDevice = null;
        pairingTimeout.stop();
        if (!root.stopWhenSettled)
            return;
        root.stopWhenSettled = false;
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = false;
    }

    Connections {
        target: root.pairingDevice

        function onPairedChanged() {
            if (root.pairingDevice?.paired)
                root.settlePairing();
        }
        function onPairingChanged() {
            if (!root.pairingDevice?.pairing)
                root.settlePairing();
        }
    }

    Timer {
        id: pairingTimeout
        // Longer than BlueZ will spend on an attempt of its own, so this only
        // ever catches a pairing that ended without saying so -- a device that
        // walked away, or an adapter reset underneath it.
        interval: 90000
        onTriggered: root.settlePairing()
    }
}
