pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

/**
 * A pen tablet as OpenTabletDriver drives it: what the tablet is, and the part
 * of its settings a person needs day to day, read from the driver's daemon and
 * handed back to it.
 *
 * What the compositor decides about the tablet, the screen it works on and
 * which hand holds the pen, is HyprInput's. Everything else the driver does,
 * the bindings of the pen's and the tablet's buttons and its filters, stays in
 * the driver's own window.
 */
Singleton {
    id: root

    readonly property string script: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/tablet/otd.py"))

    readonly property string artistMode: "OpenTabletDriver.Desktop.Output.LinuxArtistMode"
    readonly property string absoluteMode: "OpenTabletDriver.Desktop.Output.AbsoluteMode"
    readonly property string relativeMode: "OpenTabletDriver.Desktop.Output.RelativeMode"

    /** Whether the driver is on this machine at all, and whether its daemon answered. */
    property bool installed: true
    property bool running: false
    /** Whether the daemon has been asked yet. Before that, nothing above is a reading. */
    property bool ready: false
    /** What went wrong with the last change, said on the page until the next one. */
    property string lastError: ""
    property bool busy: false

    /** The tablets the daemon drives, as { name, width, height, maxPressure, penButtons, auxButtons }. */
    property var tablets: []
    property var settings: null

    /** The tablet the page is about: the first the daemon drives. */
    readonly property var tablet: root.tablets[0] ?? null
    readonly property var profile: (root.settings?.Profiles ?? []).find(entry => entry.Tablet === root.tablet?.name) ?? null
    readonly property string outputMode: root.profile?.OutputMode?.Path ?? ""
    readonly property var displayArea: root.profile?.AbsoluteModeSettings?.Display ?? null
    readonly property var tabletArea: root.profile?.AbsoluteModeSettings?.Tablet ?? null
    readonly property real tipThreshold: root.profile?.Bindings?.TipActivationThreshold ?? 0

    function refresh() {
        readState.running = false;
        readState.running = true;
    }

    /** Changes the tablet's profile, see the helper for the keys. */
    function apply(changes) {
        if (!root.tablet)
            return;
        root.lastError = "";
        root.busy = true;
        // Shown at once and corrected by the reading that follows, so a
        // switch does not sit still for a round trip through the daemon.
        if (root.profile) {
            const next = JSON.parse(JSON.stringify(root.settings));
            const profile = next.Profiles.find(entry => entry.Tablet === root.tablet.name);
            if (changes.outputMode)
                profile.OutputMode.Path = changes.outputMode;
            if (changes.displayArea)
                profile.AbsoluteModeSettings.Display = changes.displayArea;
            if (changes.tabletArea)
                profile.AbsoluteModeSettings.Tablet = changes.tabletArea;
            if (changes.tipThreshold !== undefined)
                profile.Bindings.TipActivationThreshold = changes.tipThreshold;
            root.settings = next;
        }
        applyProcess.command = ["python3", "-I", root.script, "apply", root.tablet.name, JSON.stringify(changes)];
        applyProcess.running = true;
    }

    function startDriver() {
        startProcess.running = true;
    }

    function openDriverWindow() {
        Quickshell.execDetached(["otd-gui"]);
    }

    Process {
        id: readState
        command: ["python3", "-I", root.script, "state"]
        stdout: StdioCollector {
            id: stateOut
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(stateOut.text);
                } catch (error) {
                    return;
                }
                root.installed = parsed.installed !== false;
                root.running = parsed.running === true;
                root.tablets = parsed.tablets ?? [];
                root.settings = parsed.settings ?? null;
                root.ready = true;
            }
        }
    }

    Process {
        id: applyProcess
        stderr: StdioCollector { id: applyErr }
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0)
                root.lastError = applyErr.text.trim() || Translation.tr("The tablet driver did not take the change");
            root.refresh();
        }
    }

    // A start takes the daemon a moment to come up and find the tablet, so
    // it is asked again after it rather than at once.
    Process {
        id: startProcess
        command: ["systemctl", "--user", "start", "opentabletdriver.service"]
        onExited: startedTimer.restart()
    }
    Timer {
        id: startedTimer
        interval: 1500
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
