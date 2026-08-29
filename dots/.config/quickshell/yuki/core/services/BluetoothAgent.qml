pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.core

/**
 * The pairing questions BlueZ has no other way of asking.
 *
 * Pairing is a conversation: a code to compare, a PIN to type, a device nobody
 * invited asking to connect. BlueZ puts all of it to a registered agent and
 * refuses the pairing when there is none -- so without this the shell can offer
 * a Pair button that cannot pair anything which asks a question.
 *
 * The agent itself is a process of its own, because an agent has to be a D-Bus
 * object and Quickshell can read the bus but not stand on it. It is started
 * here, it ends with the shell, and ending is what unregisters it.
 */
Singleton {
    id: root

    /**
     * Everything BlueZ is waiting on, oldest first.
     *
     * A queue rather than one at a time: a device coming back asks separately
     * for every profile it wants, and an unanswered question dropped to make
     * room for the next leaves BlueZ waiting on an answer nobody can give.
     */
    property var pending: []

    /**
     * The one being asked, straight from the agent, or nothing.
     *
     * Carries `id`, `kind`, the device's `name`, `address` and `icon`, and
     * whichever of `passkey`, `pincode`, `uuid` and `service` the kind has.
     */
    readonly property var request: root.pending.length > 0 ? root.pending[0] : null
    readonly property bool active: root.request !== null
    readonly property string kind: root.request?.kind ?? ""

    /**
     * The questions answered together with the one on screen.
     *
     * A headset wants its audio, its remote control and its handsfree profile,
     * and asks about each one by itself. They are one question to the person
     * being asked, so they are put as one and answered as one.
     */
    readonly property var groupedIds: {
        if (!root.request)
            return [];
        if (root.request.kind !== "service")
            return [root.request.id];
        return root.pending
            .filter(entry => entry.kind === "service" && entry.device === root.request.device)
            .map(entry => entry.id);
    }

    /** What those questions are asking for, named once each. */
    readonly property var services: {
        if (!root.request || root.request.kind !== "service")
            return [];
        const named = root.pending
            .filter(entry => entry.kind === "service" && entry.device === root.request.device)
            .map(entry => (entry.service ?? "").length > 0 ? entry.service : (entry.uuid ?? ""));
        return named.filter((name, index) => named.indexOf(name) === index);
    }

    /** Something to type: six digits BlueZ wants back, or a PIN of any length. */
    readonly property bool awaitingInput: root.kind === "passkey" || root.kind === "pin"
    /** Something to agree to, with nothing to type. */
    readonly property bool awaitingAnswer: root.kind === "confirm" || root.kind === "authorize" || root.kind === "service"
    /** A number to read off this screen and type on the other device. */
    readonly property bool showingCode: root.kind === "displayPasskey" || root.kind === "displayPin"

    /** The digits, whichever of the two fields the kind puts them in. */
    readonly property string code: root.request?.passkey ?? root.request?.pincode ?? ""
    /** How much of the code has been typed on the far end, while it is being watched. */
    readonly property int entered: root.request?.entered ?? 0

    /**
     * The device being asked about.
     *
     * A shown code has no answer to wait for and BlueZ never says it is over --
     * typed correctly, the pairing simply completes. What takes it off the
     * screen is this device leaving the pairing state.
     */
    readonly property BluetoothDevice device: {
        const path = root.request?.device ?? "";
        if (path.length === 0)
            return null;
        return Bluetooth.devices.values.find(candidate => candidate.dbusPath === path) ?? null;
    }

    /** Set once the agent has said BlueZ took it. */
    property bool registered: false

    function load() {
        agent.running = true;
    }

    function accept(value) {
        root.answer(true, value ?? "", false);
    }

    /**
     * Yes, and stop asking about this device.
     *
     * Trusting is what the question is really about the third time it is put:
     * the profiles a device wants are its own business once the person has said
     * the device itself is welcome.
     */
    function acceptAlways() {
        root.answer(true, "", true);
    }

    function reject() {
        // Refusing a code that was only ever shown means refusing the pairing,
        // and the agent has no way to say so: the request it was asked was
        // answered the moment it was put on screen.
        if (root.showingCode)
            root.device?.cancelPair();
        // A refusal ends the pairing, so the scan it was holding open can go
        // now rather than waiting out the timeout that guards it.
        if (root.device && root.device === BluetoothStatus.pairingDevice)
            BluetoothStatus.settlePairing();
        root.answer(false, "", false);
    }

    function answer(accepted, value, always) {
        const ids = root.groupedIds;
        if (ids.length === 0)
            return;
        for (const id of ids)
            root.send(id, accepted, value, always);
        root.pending = root.pending.filter(entry => ids.indexOf(entry.id) === -1);
    }

    function send(id, accepted, value, always) {
        if (id === undefined || id === null)
            return;
        agent.write(JSON.stringify({
            id: id,
            accept: accepted,
            value: value,
            trust: always === true
        }) + "\n");
    }

    function handle(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            console.error("[BluetoothAgent] cannot read:", line);
            return;
        }

        switch (message.event) {
        case "ready":
            root.registered = true;
            break;
        case "ask":
        case "show": {
            // A display says itself again for every digit typed on the far end,
            // which is the same question with a new count, not a second one.
            const at = root.pending.findIndex(entry => entry.id === message.id);
            if (at === -1) {
                root.pending = root.pending.concat([message]);
                break;
            }
            const next = root.pending.slice();
            next[at] = message;
            root.pending = next;
            break;
        }
        case "done":
            root.pending = root.pending.filter(entry => entry.id !== message.id);
            break;
        case "error":
            console.error("[BluetoothAgent]", message.message);
            break;
        }
    }

    Connections {
        target: root.device
        enabled: root.showingCode && root.device !== null

        function onPairingChanged() {
            if (root.device?.pairing)
                return;
            root.answer(false, "", false);
        }
    }

    /**
     * How many short-lived runs in a row.
     *
     * A helper that dies is started again, since the alternative is a session
     * that quietly stops being able to pair. One that keeps dying immediately is
     * a broken install rather than an accident, and restarting that forever
     * would spin for the rest of the session -- so the count is of runs that did
     * not last, and a run that did resets it.
     */
    property int startFailures: 0
    readonly property int startFailureLimit: 5
    /** Long enough that the run was doing its job rather than falling over. */
    readonly property int settledMs: 30000
    property double startedAt: 0

    Process {
        id: agent
        command: [`${Directories.scriptPath}/bluetooth/pairing-agent.py`]
        stdinEnabled: true

        onRunningChanged: if (agent.running) root.startedAt = Date.now()

        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.log(line)
        }

        onExited: (exitCode, exitStatus) => {
            root.pending = [];
            root.registered = false;

            if (Date.now() - root.startedAt >= root.settledMs)
                root.startFailures = 0;
            else
                root.startFailures++;

            if (root.startFailures >= root.startFailureLimit) {
                console.error("[BluetoothAgent] gave up after", root.startFailures,
                    "short runs; bluez will refuse pairing until the shell is restarted");
                return;
            }
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: agent.running = true
    }
}
