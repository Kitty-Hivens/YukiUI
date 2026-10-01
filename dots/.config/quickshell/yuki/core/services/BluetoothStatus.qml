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

    /**
     * Why the last connection asked for here did not hold, by device address:
     * "keyMissing", "refused", "unreachable" or "failed", or nothing.
     *
     * The binding's own connect() reports no reason at all, and a device whose
     * pairing went stale on its side connects for two seconds and drops: the
     * view went back to "paired" with nothing said. bluetoothctl hands back
     * the reason BlueZ gives, so connecting goes through it.
     */
    property var connectFailures: ({})
    /** What BlueZ said, for a reason the kinds above do not cover. */
    property var connectFailureDetails: ({})
    /** Addresses a connection is being asked for, before BlueZ says it is connecting. */
    property var connectingAddresses: ({})

    function connectDevice(device) {
        const address = device?.address ?? "";
        if (!/^[0-9A-Fa-f:]{17}$/.test(address) || root.connectingAddresses[address])
            return;
        root.setFailure(address, "", "");
        root.connectingAddresses = Object.assign({}, root.connectingAddresses, { [address]: true });
        connectJob.createObject(root, { address: address });
    }

    function setFailure(address: string, kind: string, detail: string) {
        const failures = Object.assign({}, root.connectFailures);
        const details = Object.assign({}, root.connectFailureDetails);
        if (kind.length > 0) {
            failures[address] = kind;
            details[address] = detail;
        } else {
            delete failures[address];
            delete details[address];
        }
        root.connectFailures = failures;
        root.connectFailureDetails = details;
    }

    function kindOfFailure(reason: string): string {
        if (/key-missing|Authentication/i.test(reason))
            return "keyMissing";
        if (/page-timeout|connection-timeout|host.?down/i.test(reason))
            return "unreachable";
        if (/refused|aborted-by-remote|abort-by-remote|not-supported|ProfileUnavailable|sdp-search/i.test(reason))
            return "refused";
        return "failed";
    }

    Component {
        id: connectJob

        Process {
            id: job

            required property string address

            running: true
            command: ["timeout", "40", "bluetoothctl", "connect", job.address]
            environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
            stdout: StdioCollector {
                id: jobOutput
            }
            onExited: exitCode => {
                const text = jobOutput.text;
                const failed = /Failed to connect: (\S+)\s*(\S*)/.exec(text);
                if (failed)
                    root.setFailure(job.address, root.kindOfFailure(`${failed[1]} ${failed[2]}`), failed[2] || failed[1]);
                else if (exitCode !== 0 && !/Connection successful/.test(text))
                    root.setFailure(job.address, "failed", exitCode === 124 ? "timeout" : "");
                const connecting = Object.assign({}, root.connectingAddresses);
                delete connecting[job.address];
                root.connectingAddresses = connecting;
                job.destroy();
            }
        }
    }

    /**
     * Pairs a device anew whose pairing went stale on its side.
     *
     * A pairing is a key both ends keep, and once one end has lost it the
     * only way back is a new one, confirmed on both screens. Nothing does
     * that by itself, since a known address that no longer has the key is
     * also what a device pretending to be it looks like. What can be spared
     * is the walk through it by hand: the old pairing is dropped, the device
     * looked for, and the pairing started, so what is left is comparing the
     * code. Connected afterwards, which is what was asked for in the first
     * place.
     *
     * `repairState` is "searching", "pairing", "notFound" or "failed", or
     * empty when nothing is going on.
     */
    property string repairAddress: ""
    property string repairName: ""
    property string repairState: ""
    property BluetoothDevice repairDevice: null

    function repair(device) {
        const address = device?.address ?? "";
        if (address.length === 0 || root.repairState === "searching" || root.repairState === "pairing")
            return;
        root.repairAddress = address;
        root.repairName = device.name || address;
        root.repairDevice = null;
        root.setFailure(address, "", "");
        root.repairState = "searching";
        device.forget();
        root.stopWhenSettled = false;
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = true;
        repairTimeout.restart();
        repairLook.restart();
    }

    /** Looks again for the device a re-pairing lost sight of. */
    function retryRepair() {
        if (root.repairAddress.length === 0 || root.repairState === "searching" || root.repairState === "pairing")
            return;
        root.repairDevice = null;
        root.repairState = "searching";
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = true;
        repairTimeout.restart();
        repairLook.restart();
    }

    function cancelRepair() {
        repairTimeout.stop();
        repairLook.stop();
        root.repairState = "";
        root.repairDevice = null;
        root.releaseDiscovery();
    }

    // A stop asked for while the search was on goes through once it is over.
    function releaseDiscovery() {
        if (!root.stopWhenSettled || root.pairing || root.repairState === "searching")
            return;
        root.stopWhenSettled = false;
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = false;
    }

    // Looked for until it shows up again, unpaired, from the scan.
    Timer {
        id: repairLook
        interval: 500
        repeat: true
        onTriggered: {
            if (root.repairState !== "searching") {
                repairLook.stop();
                return;
            }
            const found = Bluetooth.devices.values.find(device => device.address === root.repairAddress && !device.paired);
            if (!found)
                return;
            repairLook.stop();
            repairTimeout.stop();
            root.repairDevice = found;
            root.repairState = "pairing";
            root.pair(found);
        }
    }

    // Android shows itself only while its Bluetooth screen is open.
    Timer {
        id: repairTimeout
        interval: 30000
        onTriggered: {
            if (root.repairState !== "searching")
                return;
            repairLook.stop();
            root.repairState = "notFound";
            root.releaseDiscovery();
        }
    }

    Connections {
        target: root.repairDevice

        function onPairedChanged() {
            if (!root.repairDevice?.paired || root.repairState !== "pairing")
                return;
            const device = root.repairDevice;
            device.trusted = true;
            root.repairState = "";
            root.repairDevice = null;
            root.connectDevice(device);
        }
        function onPairingChanged() {
            if (root.repairDevice?.pairing || root.repairState !== "pairing")
                return;
            // Ended without the key: refused on one of the screens, or the
            // code did not match.
            if (!root.repairDevice?.paired)
                root.repairState = "failed";
        }
    }

    function startDiscovery() {
        root.stopWhenSettled = false;
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.discovering = true;
    }

    function stopDiscovery() {
        if (root.pairing || root.repairState === "searching") {
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
