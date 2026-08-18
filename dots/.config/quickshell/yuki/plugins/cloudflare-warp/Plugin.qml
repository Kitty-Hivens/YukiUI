import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.core.models.quickToggles

/**
 * Cloudflare WARP, driven through warp-cli.
 *
 * Built by the host from the manifest beside this file, not imported: nothing
 * in the shell names this type, so the directory going away takes the feature
 * with it and leaves the shell whole.
 */
QtObject {
    id: root

    /**
     * Settings, handed in by the host from the file named after this plugin.
     * Null when the host built no adapter, so every read goes through `?.`.
     */
    property var settings: null

    property bool available: false
    property bool connected: false

    /**
     * Whether the daemon has a registration of its own.
     *
     * Connecting without one fails, and the fix is `register()` -- which
     * creates an identity with Cloudflare, so it is left to be asked for.
     */
    property bool registered: true

    function fetchStatus() {
        if (!root.available)
            return;
        fetchStatusProc.running = true;
    }

    function connect() {
        if (!root.available)
            return;
        root.connected = true;
        connectProc.running = true;
    }

    function disconnect() {
        if (!root.available)
            return;
        root.connected = false;
        Quickshell.execDetached(["warp-cli", "disconnect"]);
    }

    function toggle() {
        if (root.connected)
            root.disconnect();
        else
            root.connect();
    }

    /** Creates an identity with Cloudflare. Never called on its own. */
    function register() {
        if (!root.available)
            return;
        registrationProc.running = true;
    }

    function report(body) {
        Quickshell.execDetached(["notify-send", "Cloudflare WARP", body, "-a", "Shell"]);
    }

    /** What the quick panels put on screen for this. Read by the host. */
    property QuickToggleModel quickToggle: QuickToggleModel {
        name: Translation.tr("Cloudflare WARP")
        tooltipText: Translation.tr("Cloudflare WARP (1.1.1.1)")
        icon: "cloud_lock"
        familyIcons: ({
            waffle: "cloudflare",
            iiClassic: "cloudflare-dns-symbolic"
        })
        available: root.available
        toggled: root.connected
        mainAction: () => root.toggle()
    }

    // Availability is asked of the system rather than inferred from whether the
    // status command printed anything: a daemon that is installed but not
    // running answers on stderr and leaves stdout empty, which reads the same
    // as not being installed at all.
    property Process availabilityProc: Process {
        running: true
        command: ["bash", "-c", "command -v warp-cli"]
        onExited: exitCode => {
            root.available = exitCode === 0;
            root.fetchStatus();
        }
    }

    property Process fetchStatusProc: Process {
        id: fetchStatusProc
        command: ["warp-cli", "status"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                const status = statusCollector.text;
                const wasRegistered = root.registered;
                root.registered = !status.includes("Unable");
                // Registering creates an identity with Cloudflare, so it is a
                // thing to be asked for rather than a thing that happens on the
                // way past. Off unless the settings say otherwise.
                if (wasRegistered && !root.registered && (root.settings?.autoRegister ?? false))
                    root.register();
                // Only an answer that names a state is taken. An error names
                // none, and reading it as "not connected" would report a
                // connection dropped whenever the daemon was merely busy.
                if (status.includes("Connected"))
                    root.connected = true;
                else if (status.includes("Disconnected"))
                    root.connected = false;
            }
        }
    }

    property Process connectProc: Process {
        id: connectProc
        command: ["warp-cli", "connect"]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.fetchStatus();
                return;
            }
            root.connected = false;
            root.report(root.registered //
                ? Translation.tr("Connection failed. Please inspect manually with the <tt>warp-cli</tt> command") //
                : Translation.tr("This machine is not registered with WARP yet"));
        }
    }

    property Process registrationProc: Process {
        id: registrationProc
        command: ["warp-cli", "registration", "new"]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.registered = true;
                root.connect();
                return;
            }
            root.report(Translation.tr("Registration failed. Please inspect manually with the <tt>warp-cli</tt> command"));
        }
    }
}
