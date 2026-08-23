pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.core.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    /// Device types that carry the machine online, mapped onto the channel names
    /// this service reports. Loopback, bridges, tunnels and wifi-p2p are absent on
    /// purpose: they sit at "connected (externally)" for as long as they exist, so
    /// counting them means claiming a connection that carries nothing.
    readonly property var deviceTypeChannels: ({
        "ethernet": "ethernet",
        "wifi": "wifi",
        "bt": "bluetooth",
        "gsm": "cellular",
        "cdma": "cellular",
        "wwan": "cellular"
    })
    /// The same channels as connection profiles name them.
    readonly property var connectionTypeChannels: ({
        "802-3-ethernet": "ethernet",
        "802-11-wireless": "wifi",
        "bluetooth": "bluetooth",
        "gsm": "cellular",
        "cdma": "cellular"
    })
    /// Fastest first: with several channels up, this is the one whose name and icon
    /// describe the connection.
    readonly property list<string> channelPriority: ["ethernet", "wifi", "cellular", "bluetooth"]

    property bool wifi: false
    property bool ethernet: false
    /// The channel currently carrying the connection, or "" when there is none.
    property string connectionType: ""
    readonly property bool connected: root.connectionType.length > 0
    /// NetworkManager's own verdict: none, portal, limited, full, unknown.
    property string connectivity: "unknown"
    property string wifiDevice: ""
    /// A tunnel carrying the traffic on top of whatever channel is underneath. Not a
    /// channel of its own: a tunnel is up for as long as its daemon runs, including
    /// while the link below it is dead, so counting it as connectivity would have the
    /// shell claim an internet that is not there.
    property bool vpnActive: false
    property string vpnDevice: ""

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property bool anyAskingPassword: wifiNetworks.some(n => n.askingPassword)
    /// Names of the saved wifi profiles, so a view can offer to forget one. A profile
    /// is named after its SSID unless someone renamed it by hand; forgetting matches
    /// on the SSID the profile actually carries, so a rename only costs the button.
    property list<string> savedNetworks: []
    /// The connections that carry the machine online without being wifi -- bluetooth
    /// tethering, a modem -- as {uuid, name, channel, active}. Wifi is left out: it
    /// has a list of live access points rather than of profiles.
    property list<var> otherConnections: []
    /// The connection an up/down is running for, so a view can say which row is busy.
    property string busyConnectionUuid: ""
    /// The unit that actually drives wifi, taken from what NetworkManager is
    /// configured to use rather than from which units happen to be running: both
    /// iwd and wpa_supplicant can be active at once, and only one is in the path.
    property string wifiBackendUnit: "wpa_supplicant.service"
    readonly property bool wifiBackendRestarting: restartBackendProc.running
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active !== b.active)
            return a.active ? -1 : 1;
        // By signal bars rather than by the raw number: the raw one moves a few
        // points between scans, which was enough to reorder the list under the
        // pointer every few seconds.
        const bars = s => Math.min(4, Math.floor(Math.max(0, s) / 20));
        if (bars(a.strength) !== bars(b.strength))
            return bars(b.strength) - bars(a.strength);
        return a.ssid.localeCompare(b.ssid);
    })
    property string wifiStatus: "disconnected"

    /// The active connection of each channel, by channel name.
    property var activeConnectionNames: ({})
    /// Derived rather than picked while reading, so that the name always describes
    /// the channel the icon describes: the two are read by separate processes, and
    /// whichever finished last used to decide what the bar said.
    readonly property string networkName: root.activeConnectionNames[root.connectionType] ?? ""
    property int networkStrength
    property string materialSymbol: {
        if (root.connectionType === "ethernet")
            return "lan";
        if (root.connectionType === "cellular")
            return "signal_cellular_alt";
        // Not a bluetooth glyph: tethering sits next to the bluetooth toggle in the
        // panel, and two bluetooth marks side by side say nothing about the internet.
        if (root.connectionType === "bluetooth")
            return "wifi";
        if (root.wifiStatus === "limited")
            return "signal_wifi_bad";
        if (root.connectionType === "wifi") {
            // The access point list and the device state are read by separate
            // processes, so right after joining, the strength can still be unknown;
            // the last figure the strength process reported stands in for it rather
            // than dropping the icon to empty bars.
            const strength = root.active?.strength ?? root.networkStrength;
            if (strength > 83) return "signal_wifi_4_bar";
            if (strength > 67) return "network_wifi";
            if (strength > 50) return "network_wifi_3_bar";
            if (strength > 33) return "network_wifi_2_bar";
            if (strength > 17) return "network_wifi_1_bar";
            return "signal_wifi_0_bar";
        }
        if (root.wifiStatus === "connecting")
            return "signal_wifi_statusbar_not_connected";
        if (root.wifiStatus === "disabled")
            return "signal_wifi_off";
        return "wifi_find";
    }

    /// Splits one line of `nmcli -t` output into its fields. The separator is a
    /// colon, and a colon inside a field arrives backslash-escaped -- which BSSIDs
    /// always are, and SSIDs are free to be.
    function splitEscaped(line: string): var {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                current += line[++i];
            } else if (c === ":") {
                fields.push(current);
                current = "";
            } else {
                current += c;
            }
        }
        fields.push(current);
        return fields;
    }

    // Control
    function enableWifi(enabled = true): void {
        if (enableWifiProc.running)
            return;
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        if (rescanProcess.running)
            return;
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint, password = ""): void {
        if (!accessPoint)
            return;
        // One attempt at a time, all the way down: the second one would restart a
        // Process that is still alive, which is the crash the note above update()
        // describes. The views grey their buttons out while an attempt runs, and
        // this is the same rule where nothing is watching the buttons.
        if (connectProc.running)
            return;
        accessPoint.askingPassword = false;
        accessPoint.errorKind = "";
        accessPoint.errorDetail = "";
        root.wifiConnectTarget = accessPoint;
        root.connectAttemptHadPassword = password.length > 0;
        root.connectErrorKind = "";
        root.connectErrorDetail = "";
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile.
        // The SSID and the password travel in the environment rather than in the
        // argument list, which every process on the machine can read.
        connectProc.exec({
            "environment": {
                "LANG": "C",
                "LC_ALL": "C",
                "SSID": accessPoint.ssid,
                "PASSWORD": password
            },
            "command": ["bash", "-c", password.length > 0
                ? 'nmcli dev wifi connect "$SSID" password "$PASSWORD"'
                : 'nmcli dev wifi connect "$SSID"']
        });
    }

    function disconnectWifiNetwork(): void {
        if (disconnectProc.running)
            return;
        // By device rather than by profile name: a profile is not required to be
        // named after its SSID, and a failed attempt is exactly what leaves a
        // second one ("SSID 1") behind to be named after it instead.
        if (root.wifiDevice.length > 0)
            disconnectProc.exec(["nmcli", "device", "disconnect", root.wifiDevice]);
        else if (root.active)
            disconnectProc.exec(["nmcli", "connection", "down", "id", root.active.ssid]);
    }

    function forgetWifiNetwork(accessPoint: WifiAccessPoint): void {
        if (!accessPoint || forgetProc.running)
            return;
        accessPoint.askingPassword = false;
        accessPoint.errorKind = "";
        accessPoint.errorDetail = "";
        // Every wifi profile is matched on the SSID it carries rather than on its
        // name, so that a renamed profile is still found and the duplicates a failed
        // attempt leaves behind go with it.
        forgetProc.exec({
            "environment": {
                "LANG": "C",
                "LC_ALL": "C",
                "SSID": accessPoint.ssid
            },
            "command": ["bash", "-c", 'nmcli -g UUID,TYPE connection show | while IFS=: read -r uuid type; do [ "$type" = "802-11-wireless" ] || continue; [ "$(nmcli -g 802-11-wireless.ssid connection show "$uuid")" = "$SSID" ] && nmcli connection delete "$uuid"; done']
        });
    }

    // Up and down share the guard rather than each watching only itself: they act
    // on the same connections, and taking one down while another is coming up is
    // two nmcli runs deciding between them what the machine ends up on.
    readonly property bool connectionBusy: connectionUpProc.running || connectionDownProc.running

    function activateConnection(uuid: string): void {
        if (root.connectionBusy)
            return;
        root.busyConnectionUuid = uuid;
        connectionUpProc.exec(["nmcli", "connection", "up", "uuid", uuid]);
    }

    function deactivateConnection(uuid: string): void {
        if (root.connectionBusy)
            return;
        root.busyConnectionUuid = uuid;
        connectionDownProc.exec(["nmcli", "connection", "down", "uuid", uuid]);
    }

    /// Restarts the wifi backend. The scan list comes from that daemon, so when it
    /// stops answering -- iwd reporting a scan already in progress while claiming it
    /// is not scanning -- nothing above it can recover on its own.
    function restartWifiBackend(): void {
        if (restartBackendProc.running)
            return;
        // Through systemctl rather than pkexec, so the polkit prompt names the unit
        // being restarted and the shell's own agent is what answers it.
        restartBackendProc.exec(["systemctl", "restart", root.wifiBackendUnit]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        // One `nmcli dev wifi connect ... password ...` rather than a modify of the
        // profile followed by a retry: for a network never joined before there is no
        // profile of that name to modify, so the modify failed, the retry went out
        // without the password, and the prompt came straight back.
        root.connectToWifiNetwork(network, password);
    }

    // Failure of the attempt in flight, gathered from stderr as it arrives and
    // applied to the network being joined.
    property string connectErrorKind: ""
    property string connectErrorDetail: ""
    property bool connectAttemptHadPassword: false

    function noteConnectFailure(line: string): void {
        // nmcli words a missing password and a wrong one identically, so which of
        // the two it is only follows from whether this attempt carried one.
        if (line.includes("Secrets were required") || line.includes("secrets were required")
            || line.includes("no secrets provided") || line.includes("encryption keys are required")) {
            root.connectErrorKind = root.connectAttemptHadPassword ? "wrongPassword" : "secrets";
        } else if (line.includes("No network with SSID")) {
            root.connectErrorKind = "notFound";
        } else if (line.includes("timeout") || line.includes("timed out")) {
            if (root.connectErrorKind.length === 0)
                root.connectErrorKind = "timeout";
        } else if (line.startsWith("Error:")) {
            if (root.connectErrorKind.length === 0)
                root.connectErrorKind = "failed";
            root.connectErrorDetail = line.replace(/^Error:\s*/, "");
        }
        root.applyConnectFailure(root.wifiConnectTarget);
    }

    function applyConnectFailure(network: WifiAccessPoint): void {
        if (!network || root.connectErrorKind.length === 0)
            return;
        network.errorKind = root.connectErrorKind;
        network.errorDetail = root.connectErrorDetail;
        // A password is only asked for when the password is what was missing. Every
        // other failure -- out of range, DHCP timeout -- used to raise the same
        // prompt, which said the password was wrong when it was not.
        network.askingPassword = (root.connectErrorKind === "secrets" || root.connectErrorKind === "wrongPassword");
    }

    Process {
        id: enableWifiProc
        onExited: root.update()
    }

    Process {
        id: connectProc
        stderr: SplitParser {
            onRead: line => root.noteConnectFailure(line)
        }
        // Nothing to report back to once the attempt is over, and the access point
        // can also go out from under us: the list is rebuilt while connecting, and
        // an entry is replaced whenever the strongest transmitter for its name
        // changes -- which is exactly what joining it does.
        onExited: (exitCode, exitStatus) => {
            const target = root.wifiConnectTarget;
            root.wifiConnectTarget = null;
            if (target) {
                if (exitCode === 0) {
                    target.askingPassword = false;
                    target.errorKind = "";
                    target.errorDetail = "";
                } else {
                    // Nothing recognisable on stderr and a non-zero exit still means
                    // the attempt failed, and the view has to be able to say so.
                    if (root.connectErrorKind.length === 0)
                        root.connectErrorKind = "failed";
                    root.applyConnectFailure(target);
                }
            }
            root.update();
        }
    }

    Process {
        id: disconnectProc
        onExited: root.update()
    }

    Process {
        id: forgetProc
        onExited: root.update()
    }

    Process {
        id: wifiBackendProcess
        running: true
        command: ["sh", "-c", "grep -rhiE '^[[:space:]]*wifi\\.backend[[:space:]]*=' /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/*.conf 2>/dev/null | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const configured = text.trim().split("=").pop().trim().toLowerCase();
                root.wifiBackendUnit = (configured === "iwd") ? "iwd.service" : "wpa_supplicant.service";
            }
        }
    }

    Process {
        id: restartBackendProc
        onExited: (exitCode, exitStatus) => {
            root.update();
            // The daemon needs a moment to bring the device back before a scan means
            // anything; asking too early just returns the empty list it starts with.
            if (exitCode === 0)
                backendSettleTimer.restart();
        }
    }

    Timer {
        id: backendSettleTimer
        interval: 3000
        onTriggered: {
            root.update();
            root.rescanWifi();
        }
    }

    Process {
        id: connectionUpProc
        onExited: {
            root.busyConnectionUuid = "";
            root.update();
        }
    }

    Process {
        id: connectionDownProc
        onExited: {
            root.busyConnectionUuid = "";
            root.update();
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // Collected rather than read line by line: the listing is one line per
        // network, and each of them used to start the process that reads the network
        // list -- the same "start a process that is already running" that the comment
        // on update() below is about.
        stdout: StdioCollector {
            onStreamFinished: root.refreshNetworks()
        }
        // Cleared when the process goes away rather than on its first line of output:
        // a scan that prints nothing, or one that never starts, otherwise leaves the
        // progress bar spinning and the rescan button disabled for good.
        onRunningChanged: if (!rescanProcess.running) root.wifiScanning = false
    }

    // Status update
    //
    // `nmcli monitor` reports a wifi state change as several lines inside the same
    // second -- radio off and on, scan, associate, DHCP, connected -- and each of
    // them arrives here. Starting a Process that is already running races the
    // teardown of the stdout callback still in flight, which crashes the shell, so
    // a call that lands mid-batch is remembered and re-run once the batch is done.
    property bool pendingUpdate: false
    property bool pendingNetworksRefresh: false
    readonly property bool updateInFlight: updateConnectionType.running || wifiStatusProcess.running
        || updateNetworkName.running || updateNetworkStrength.running || savedProfilesProcess.running
        || getNetworks.running

    function update() {
        if (root.updateInFlight) {
            root.pendingUpdate = true;
            return;
        }
        updateConnectionType.running = true;
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
        savedProfilesProcess.running = true;
        root.refreshNetworks();
    }

    /// The network list on its own, for the callers that only need that much. Same
    /// deal as update(): a request that lands while the read is in flight waits for
    /// it rather than restarting it.
    function refreshNetworks(): void {
        if (getNetworks.running) {
            root.pendingNetworksRefresh = true;
            return;
        }
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
    // and triggers a NetworkManager autoconnect re-evaluation. Not while a
    // connection is being dealt with, for the reason on the timer below.
    onWifiStatusChanged: if (wifiStatus !== "connected" && !root.wifiConnecting && !root.anyAskingPassword) rescanWifi();

    // Background scan keeps the list current and autoconnect re-evaluated even
    // with no monitor events; tighter cadence while disconnected.
    //
    // Held off while a password is being typed or an attempt is in flight: a scan
    // re-associates the radio and has NetworkManager reconsider autoconnect, so the
    // list moved, entries were replaced and the half-typed password went with them.
    Timer {
        id: autoRescanTimer
        running: root.wifiEnabled && !root.wifiConnecting && !root.anyAskingPassword
        repeat: true
        triggeredOnStart: true
        interval: (root.wifiStatus === "connected") ? 30000 : 15000
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
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,DEVICE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
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
                let channels = [];
                let wifiStatus = "disconnected";
                let wifiDevice = "";
                let vpnDevice = "";
                lines.forEach(line => {
                    // Read as TYPE and STATE, not searched for words: "disconnected"
                    // contains "connected", so a wired device sitting idle counted as
                    // a live one and the bar showed a wired icon with no wifi behind
                    // it. States carry suffixes such as "connected (externally)".
                    const fields = root.splitEscaped(line);
                    if (fields.length < 2)
                        return;
                    const type = fields[0];
                    const state = fields[1];
                    // Every channel counts, not only wifi and ethernet: with the
                    // machine online over bluetooth tethering or a modem, those two
                    // are both down and the shell used to report no connection at all.
                    const channel = root.deviceTypeChannels[type] ?? "";
                    if (type === "wifi") {
                        wifiDevice = fields[2] ?? "";
                        if (state.startsWith("disconnected")) {
                            wifiStatus = "disconnected";
                        } else if (state.startsWith("connected")) {
                            wifiStatus = "connected";
                        } else if (state.startsWith("connecting")) {
                            wifiStatus = "connecting";
                        } else if (state.startsWith("unavailable")) {
                            wifiStatus = "disabled";
                        }
                    }
                    if (channel.length > 0 && state.startsWith("connected") && !channels.includes(channel))
                        channels.push(channel);
                    if ((type === "tun" || type === "wireguard" || type === "vpn") && state.startsWith("connected"))
                        vpnDevice = fields[2] ?? "";
                });
                // Decided after the whole listing is read rather than per line, so
                // that the tunnel is already known about: NetworkManager reaches its
                // connectivity check through the tunnel and calls a working connection
                // "limited", which used to put a broken-network icon on a fine one.
                if (connectivity === "limited" && wifiStatus === "connected" && vpnDevice.length === 0)
                    wifiStatus = "limited";
                root.connectivity = connectivity;
                root.wifiDevice = wifiDevice;
                root.vpnDevice = vpnDevice;
                root.vpnActive = vpnDevice.length > 0;
                root.connectionType = root.channelPriority.find(c => channels.includes(c)) ?? "";
                root.ethernet = channels.includes("ethernet");
                root.wifi = channels.includes("wifi") && wifiStatus === "connected";
                root.wifiStatus = wifiStatus;
            }
        }
    }

    Process {
        id: updateNetworkName
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "c", "show", "--active"]
        running: true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // Picked by channel rather than by taking the first line: the order the
        // active connections come in is nobody's promise, and loopback, bridges and
        // tunnels are in there too, so the name on the bar -- and in the keyword
        // check that decides whether to cover the screen -- could end up being "lo".
        //
        // Collected rather than read line by line for the same reason as the strength
        // below: nothing connected means no line at all, and a per-line reader is
        // simply never called, so the name last seen stayed for the rest of the session.
        stdout: StdioCollector {
            onStreamFinished: {
                let names = ({});
                text.trim().split("\n").filter(line => line.length > 0).forEach(line => {
                    const fields = root.splitEscaped(line);
                    const channel = root.connectionTypeChannels[fields[1]] ?? "";
                    // First one wins: a channel with several profiles up is carrying
                    // the first of them, and the rest are along for the ride.
                    if (channel.length > 0 && !names[channel])
                        names[channel] = fields[0];
                });
                root.activeConnectionNames = names;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["nmcli", "-g", "IN-USE,SIGNAL", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // Same reason as the name above: there is no line to read while disconnected.
        stdout: StdioCollector {
            onStreamFinished: {
                const inUse = text.trim().split("\n").find(line => line.startsWith("*"));
                root.networkStrength = inUse ? (parseInt(root.splitEscaped(inUse)[1]) || 0) : 0;
            }
        }
    }

    Process {
        id: savedProfilesProcess
        running: true
        command: ["nmcli", "-t", "-f", "UUID,NAME,TYPE,ACTIVE", "c", "show"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const profiles = text.trim().split("\n")
                    .filter(line => line.length > 0)
                    .map(line => root.splitEscaped(line));
                root.savedNetworks = profiles
                    .filter(fields => fields[2] === "802-11-wireless")
                    .map(fields => fields[1]);
                root.otherConnections = profiles
                    .map(fields => ({
                        uuid: fields[0],
                        name: fields[1],
                        channel: root.connectionTypeChannels[fields[2]] ?? "",
                        active: fields[3] === "yes"
                    }))
                    // Wifi has its own list, and ethernet is not something to pick
                    // from a list -- it is up whenever the cable is in.
                    .filter(c => c.channel === "bluetooth" || c.channel === "cellular");
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
        onRunningChanged: {
            if (getNetworks.running || !root.pendingNetworksRefresh)
                return;
            root.pendingNetworksRefresh = false;
            root.refreshNetworks();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // No networks at all is empty output, which splits into one empty
                // line and used to become a nameless access point in the list.
                const allNetworks = text.trim().split("\n").filter(n => n.length > 0).map(n => {
                    const net = root.splitEscaped(n);
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3] ?? "",
                        bssid: net[4] ?? "",
                        security: net[5] ?? ""
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

                // Matched on the SSID alone, because that is what the list is keyed
                // by: matching on the transmitter and the band as well meant that
                // roaming to another transmitter, or the strongest one for a name
                // simply changing between scans, destroyed the entry and built a new
                // one -- taking the password prompt, and whatever had been typed into
                // it, with it. An entry being joined or holding a prompt is kept even
                // when a scan stops reporting it, which is what joining it does.
                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.ssid === rn.ssid)
                    && !rn.askingPassword && rn !== root.wifiConnectTarget);
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.ssid === network.ssid);
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
