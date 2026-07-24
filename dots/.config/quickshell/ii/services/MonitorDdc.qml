pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The monitor's own controls, over DDC/CI.
 *
 * These are the panel's hardware settings, distinct from anything the compositor
 * does. The list is read from each monitor rather than fixed, so a display that
 * exposes more shows more; the compositor stays the single owner of everything
 * it can express, and only controls with no source-side equivalent surface here.
 *
 * Every write is confirmed by reading the value back, because some controllers
 * accept a write and quietly ignore it, and a control that lies is worse than
 * one that is missing.
 */
Singleton {
    id: root

    // Standard MCCS controls with no compositor equivalent. The intersection of
    // this and what a monitor advertises is what gets shown. Raw vendor codes
    // are deliberately not exposed as blind sliders: that is how a controller
    // gets wedged. Colour, geometry, brightness and power are all owned by the
    // compositor and excluded on purpose.
    readonly property var allowlist: ({
        "12": { label: "Contrast", icon: "contrast", order: 0 },
        "87": { label: "Sharpness", icon: "deblur", order: 1 },
        "60": { label: "Input source", icon: "cable", order: 2 },
        "CC": { label: "OSD language", icon: "translate", order: 3 }
    })

    // Structure only: connector -> { bus, features: [ { vcp, kind, name, icon,
    // order, values:[{code,label}] } ] }. Never reassigned on a value read, so
    // the controls built from it are not rebuilt under the pointer.
    property var monitors: ({})
    // Live values, kept apart from the structure so updating one does not churn
    // the other. Keyed "connector\tvcp" -> { current, max }.
    property var values: ({})
    property bool probing: false
    property string lastError: ""

    function currentOf(connector, vcp) {
        return root.values[`${connector}\t${vcp}`]?.current ?? -1;
    }

    function maxOf(connector, vcp) {
        return root.values[`${connector}\t${vcp}`]?.max ?? 100;
    }

    readonly property string scriptDir: `${FileUtils.trimFileProtocol(Directories.config)}/quickshell/ii/scripts/displays`

    function featuresFor(connector) {
        return root.monitors[connector]?.features ?? [];
    }

    function hasControls(connector) {
        return root.featuresFor(connector).length > 0;
    }

    function reload() {
        if (root.probing)
            return;
        root.probing = true;
        probe.running = true;
    }

    Process {
        id: probe
        command: ["python3", `${root.scriptDir}/ddc_probe.py`]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: {
                const found = ({});
                for (const line of probeOut.text.trim().split("\n")) {
                    if (line.length === 0)
                        continue;
                    const cols = line.split("\t");
                    if (cols.length < 4)
                        continue;
                    const [connector, bus, vcp, kind] = cols;
                    const name = cols[4] ?? "";
                    const raw = cols[5] ?? "";
                    if (!root.allowlist[vcp])
                        continue;

                    const values = raw.length === 0 ? [] : raw.split("|").map(pair => {
                        const eq = pair.indexOf("=");
                        return { code: pair.slice(0, eq), label: pair.slice(eq + 1) };
                    });

                    if (!found[connector])
                        found[connector] = { bus: bus, features: [] };
                    found[connector].features.push({
                        vcp: vcp,
                        kind: kind,
                        name: root.allowlist[vcp].label,
                        icon: root.allowlist[vcp].icon,
                        order: root.allowlist[vcp].order,
                        values: values
                    });
                }
                for (const connector in found)
                    found[connector].features.sort((a, b) => a.order - b.order);
                root.monitors = found;
                root.readCurrentValues();
            }
        }
        onExited: root.probing = false
    }

    // One getvcp per monitor for all its allowlisted codes at once, so the
    // controls open showing where the monitor actually is rather than blank.
    function readCurrentValues() {
        const connectors = Object.keys(root.monitors);
        if (connectors.length === 0)
            return;
        readValues.connectorQueue = connectors;
        root.readNextConnector();
    }

    property var readQueue: []

    function readNextConnector() {
        if (readValues.connectorQueue.length === 0)
            return;
        const connector = readValues.connectorQueue.shift();
        const entry = root.monitors[connector];
        readValues.connector = connector;
        readValues.command = ["ddcutil", "-b", entry.bus, "getvcp", "--brief"]
            .concat(entry.features.map(f => f.vcp));
        readValues.running = true;
    }

    Process {
        id: readValues
        property var connectorQueue: []
        property string connector: ""
        stdout: StdioCollector {
            id: valuesOut
            onStreamFinished: {
                // Brief getvcp: "VCP 12 C 50 100" (continuous, value + max) or
                // "VCP 60 SNC x0f" (a named value in hex).
                const entry = root.monitors[readValues.connector];
                if (!entry) {
                    root.readNextConnector();
                    return;
                }
                const updated = Object.assign({}, root.values);
                for (const line of valuesOut.text.trim().split("\n")) {
                    const parts = line.trim().split(/\s+/);
                    if (parts[0] !== "VCP" || parts.length < 4)
                        continue;
                    const vcp = parts[1].toUpperCase();
                    if (!entry.features.some(f => f.vcp === vcp))
                        continue;
                    const key = `${readValues.connector}\t${vcp}`;
                    if (parts[2] === "C")
                        updated[key] = { current: parseInt(parts[3]), max: parseInt(parts[4] ?? "100") };
                    else
                        updated[key] = { current: parseInt((parts[3] ?? "x0").replace("x", ""), 16), max: 100 };
                }
                root.values = updated;
                root.readNextConnector();
            }
        }
    }

    /**
     * Set a control and confirm it landed. The value is applied, then read back;
     * the reported value is always the real one, so a control that did not take
     * snaps back rather than lying about a change that never happened.
     */
    // Dragging a slider emits continuously. Reassigning a process still running
    // loses calls, and the lost one can be the last, so only the newest value
    // per control is kept while a write is in flight.
    property var pendingWrite: null

    function setValue(connector, vcp, value) {
        const entry = root.monitors[connector];
        if (!entry)
            return;
        root.lastError = "";
        root.pendingWrite = { connector: connector, vcp: vcp, value: value, bus: entry.bus };
        if (!writeProc.running)
            root.flushWrite();
    }

    function flushWrite() {
        const next = root.pendingWrite;
        if (!next || writeProc.running)
            return;
        root.pendingWrite = null;
        writeProc.connector = next.connector;
        writeProc.command = ["ddcutil", "-b", next.bus, "setvcp", next.vcp, `${next.value}`];
        writeProc.running = true;
    }

    Process {
        id: writeProc
        property string connector: ""
        stderr: StdioCollector { id: writeErr }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.lastError = Translation.tr("The monitor did not accept the change: %1").arg(writeErr.text.trim());
            // A newer value arrived mid-write: send it before reading back, so
            // the confirmation reflects where the control actually ended up.
            if (root.pendingWrite) {
                root.flushWrite();
                return;
            }
            // Read back only once the changes stop, and after a beat: the panel
            // applies a write a little after ddcutil returns, and reading too
            // soon reports the previous value. Restarting the timer per write
            // means it fires once the interaction is over.
            settleTimer.connector = writeProc.connector;
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        property string connector: ""
        interval: 400
        onTriggered: {
            if (root.monitors[settleTimer.connector]) {
                readValues.connectorQueue = [settleTimer.connector];
                root.readNextConnector();
            }
        }
    }

    Component.onCompleted: root.reload()
}
