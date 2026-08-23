import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.core.models.quickToggles

/**
 * A VPN that lives in a systemd unit rather than in NetworkManager: sing-box,
 * a wg-quick unit, an openvpn service.
 *
 * Which unit is a setting rather than a name in this file, so the same plugin
 * serves whatever is installed. With no unit named it stays unavailable, and
 * the toggle is not drawn at all.
 */
QtObject {
    id: root

    /**
     * Settings, handed in by the host from the file named after this plugin.
     * Null when the host built no adapter, so every read goes through `?.`.
     */
    property var settings: null

    readonly property string unit: root.settings?.unit ?? ""
    readonly property string label: {
        const configured = root.settings?.label ?? "";
        return configured.length > 0 ? configured : Translation.tr("VPN");
    }
    /**
     * Units to bring down together with the tunnel, space separated.
     *
     * A kill-switch is the case this exists for: it is pulled up by the tunnel
     * and outlives it, so stopping the tunnel alone leaves a machine with no way
     * out and no obvious reason why.
     */
    readonly property list<string> alsoStop: (root.settings?.alsoStop ?? "").split(" ").filter(unit => unit.length > 0)

    property bool available: false
    readonly property bool busy: startProc.running || stopProc.running
    /**
     * Whether the tunnel is up.
     *
     * Read from the interface existing rather than from the unit calling itself
     * active: the unit is what starts the tunnel, the interface is what carries
     * the traffic, and a unit that is up while its tunnel is gone is exactly the
     * state worth showing as off.
     */
    readonly property bool connected: Network.vpnActive

    function checkAvailability(): void {
        if (root.unit.length === 0) {
            root.available = false;
            return;
        }
        availabilityProc.exec(["systemctl", "show", "-p", "LoadState", "--value", root.unit]);
    }

    // Settings arrive after construction, so availability is asked again for
    // whatever unit ends up being named rather than once for the empty default.
    onUnitChanged: root.checkAvailability()

    function connect(): void {
        if (!root.available || root.busy)
            return;
        // Plain systemctl rather than pkexec: polkit then names the unit in its
        // prompt, and the shell's own agent is what answers it.
        startProc.exec(["systemctl", "start", root.unit]);
    }

    function disconnect(): void {
        if (!root.available || root.busy)
            return;
        stopProc.exec(["systemctl", "stop", root.unit].concat(root.alsoStop));
    }

    function toggle(): void {
        if (root.connected)
            root.disconnect();
        else
            root.connect();
    }

    function report(body): void {
        Quickshell.execDetached(["notify-send", root.label, body, "-a", "Shell"]);
    }

    /** What the quick panels put on screen for this. Read by the host. */
    property QuickToggleModel quickToggle: QuickToggleModel {
        name: root.label
        statusText: {
            if (root.busy)
                return root.connected ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
            return root.connected ? Network.vpnDevice : Translation.tr("Off");
        }
        tooltipText: root.connected
            ? Translation.tr("Through %1").arg(Network.vpnDevice)
            : Translation.tr("%1 is off").arg(root.label)
        icon: "vpn_lock"
        familyIcons: ({
            waffle: "shield-lock",
            iiClassic: "network-vpn-symbolic"
        })
        available: root.available
        toggled: root.connected
        mainAction: () => root.toggle()
    }

    // Asked of systemd rather than of the filesystem: a unit can come from any of
    // several directories, and "not-found" is the one answer that covers all of
    // them plus a name with a typo in it.
    property Process availabilityProc: Process {
        id: availabilityProc
        stdout: StdioCollector {
            id: loadState
            onStreamFinished: root.available = (loadState.text.trim() === "loaded")
        }
    }

    property Process startProc: Process {
        id: startProc
        onExited: exitCode => {
            if (exitCode !== 0)
                root.report(Translation.tr("Could not start %1").arg(root.unit));
        }
    }

    property Process stopProc: Process {
        id: stopProc
        onExited: exitCode => {
            if (exitCode !== 0)
                root.report(Translation.tr("Could not stop %1").arg(root.unit));
        }
    }
}
