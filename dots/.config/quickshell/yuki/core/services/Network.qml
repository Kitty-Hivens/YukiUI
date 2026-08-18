pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                (root.active?.strength ?? 0) > 83 ? "signal_wifi_4_bar" :
                (root.active?.strength ?? 0) > 67 ? "network_wifi" :
                (root.active?.strength ?? 0) > 50 ? "network_wifi_3_bar" :
                (root.active?.strength ?? 0) > 33 ? "network_wifi_2_bar" :
                (root.active?.strength ?? 0) > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        // The retry below runs the connect process again without going through
        // connectToWifiNetwork, so the network it is for has to be named here.
        root.wifiConnectTarget = network;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required") && root.wifiConnectTarget) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        // Nothing to report back to once the attempt is over, and the access point
        // can also go out from under us: the list is rebuilt while connecting, and
        // an entry is replaced whenever the strongest transmitter for its name
        // changes -- which is exactly what joining it does.
        onExited: (exitCode, exitStatus) => {
            if (root.wifiConnectTarget)
                root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }

    // Status update
    //
    // `nmcli monitor` reports a wifi state change as several lines inside the same
    // second -- radio off and on, scan, associate, DHCP, connected -- and each of
    // them arrives here. Starting a Process that is already running races the
    // teardown of the stdout callback still in flight, which crashes the shell, so
    // a call that lands mid-batch is remembered and re-run once the batch is done.
    property bool pendingUpdate: false
    readonly property bool updateInFlight: updateConnectionType.running || wifiStatusProcess.running
        || updateNetworkName.running || updateNetworkStrength.running || getNetworks.running

    function update() {
        if (root.updateInFlight) {
            root.pendingUpdate = true;
            return;
        }
        updateConnectionType.running = true;
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
        getNetworks.running = true;
    }

    // Watched rather than driven from each process's onExited: a process that fails
    // to launch at all never reports an exit, and `running` is the one signal that
    // arrives either way.
    onUpdateInFlightChanged: {
        if (root.updateInFlight || !root.pendingUpdate)
            return;
        root.pendingUpdate = false;
        root.update();
    }

    // Re-scan on every transition out of "connected": refreshes the AP list
    // and triggers a NetworkManager autoconnect re-evaluation.
    onWifiStatusChanged: if (wifiStatus !== "connected") rescanWifi();

    // Background scan keeps the list current and autoconnect re-evaluated even
    // with no monitor events; tighter cadence while disconnected.
    Timer {
        id: autoRescanTimer
        running: root.wifiEnabled
        repeat: true
        triggeredOnStart: true
        interval: (root.wifiStatus === "connected") ? 30000 : 7000
        onTriggered: root.rescanWifi()
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        // Collected per run rather than appended to a buffer of our own. Asking for
        // a re-check while one was still in flight emptied that buffer under it, and
        // the run that was already going then read whatever had arrived since --
        // usually nothing, which parses as every device being down. The bar dropped
        // to disconnected, and the rescan that answers a lost connection fired on a
        // connection that had never been lost.
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                const connectivity = lines.pop() // none, limited, full
                let hasEthernet = false;
                let hasWifi = false;
                let wifiStatus = "disconnected";
                lines.forEach(line => {
                    // Read as TYPE and STATE, not searched for words: "disconnected"
                    // contains "connected", so a wired device sitting idle counted as
                    // a live one and the bar showed a wired icon with no wifi behind
                    // it. States carry suffixes such as "connected (externally)".
                    const separator = line.indexOf(":");
                    if (separator < 0)
                        return;
                    const type = line.slice(0, separator);
                    const state = line.slice(separator + 1);
                    if (type === "ethernet") {
                        if (state.startsWith("connected"))
                            hasEthernet = true;
                    }
                    else if (type === "wifi") {
                        if (state.startsWith("disconnected")) {
                            wifiStatus = "disconnected"
                        }
                        else if (state.startsWith("connected")) {
                            hasWifi = true;
                            wifiStatus = "connected"

                            if (connectivity === "limited") {
                                hasWifi = false;
                                wifiStatus = "limited"
                            }
                        }
                        else if (state.startsWith("connecting")) {
                            wifiStatus = "connecting"
                        }
                        else if (state.startsWith("unavailable")) {
                            wifiStatus = "disabled"
                        }
                    }
                });
                root.wifiStatus = wifiStatus;
                root.ethernet = hasEthernet;
                root.wifi = hasWifi;
            }
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        // Collected rather than read line by line: nothing connected means no line
        // at all, and a per-line reader is simply never called, so the name of the
        // network last joined stayed on the bar for the rest of the session -- and
        // stayed in the keyword check that decides whether to cover the screen.
        stdout: StdioCollector {
            onStreamFinished: {
                root.networkName = text.trim();
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        // Same reason as the name above: awk prints nothing while disconnected.
        stdout: StdioCollector {
            onStreamFinished: {
                root.networkStrength = parseInt(text.trim()) || 0;
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                // No networks at all is empty output, which splits into one empty
                // line and used to become a nameless access point in the list.
                const allNetworks = text.trim().split("\n").filter(n => n.length > 0).map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        // Every field the placeholder can reach has to be put back,
                        // not only the address: an SSID carrying a colon kept the
                        // placeholder, and since that string is what goes into
                        // `nmcli dev wifi connect` and its siblings, such a network
                        // could be neither joined nor left from here.
                        frequency: parseInt(net[2]),
                        ssid: net[3]?.replace(rep2, ":") ?? "",
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5]?.replace(rep2, ":") ?? ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
