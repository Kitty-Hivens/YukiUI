pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire

import qs.core
import qs.core.functions

/**
 * Who is capturing: a program using a microphone or a camera, recording the
 * sound that is playing, or taking the screen, and whether the screen
 * recording the shell starts is running.
 *
 * PipeWire names the programs using a microphone or a camera, recording the
 * sound or taking the screen through the portal. A program taking the screen
 * straight from the compositor is named by the capture-report plugin, which
 * reports every program taking it whenever that changes. Without the plugin
 * such a program is not shown: the compositor alone says the screen is being
 * taken, and not by whom.
 */
Singleton {
    id: root

    function load() {}

    // -- What PipeWire says ---------------------------------------------------

    /** Every stream taking something in: sound, or a picture. */
    readonly property var consumers: (Pipewire.nodes?.values ?? []).filter(node => node.isStream && !node.isSink)

    // Properties come with a node that is tracked: the streams taking
    // something in, and what they take from.
    PwObjectTracker {
        objects: {
            const tracked = [];
            for (const node of root.consumers)
                tracked.push(node);
            for (const group of Pipewire.linkGroups?.values ?? []) {
                if (group.source && tracked.includes(group.target) && !tracked.includes(group.source))
                    tracked.push(group.source);
            }
            return tracked;
        }
    }

    /**
     * What a stream is doing, from what it is and what it takes from:
     * "microphone", "sound", "camera" or "screen", or empty for nothing to
     * show. `linked` is whether it takes from anything, `fromOutput` whether
     * from an output, which is the sound playing, `fromScreen` whether from the
     * portal's screen cast. A picture from anywhere else is a camera.
     *
     * The shell's own streams, a level meter say, and a sound processor in the
     * way of every program, EasyEffects, are left out: they would show for
     * good and hide the programs behind them.
     *
     * Handed plain values: a list of what it takes from, handed in, arrived as
     * an object without a list's methods.
     */
    function kindOf(mediaClass: string, binary: string, nodeName: string, linked: bool, fromOutput: bool, fromScreen: bool): string {
        if (binary === "quickshell" || binary === "qs" || nodeName.startsWith("easyeffects_") || !linked)
            return "";
        if (mediaClass.startsWith("Stream/Input/Video"))
            return fromScreen ? "screen" : "camera";
        if (mediaClass.startsWith("Stream/Input/Audio"))
            return fromOutput ? "sound" : "microphone";
        return "";
    }

    function displayName(node): string {
        const properties = node.properties ?? {};
        if ((properties["media.class"] ?? "").startsWith("Stream/Input/Audio"))
            return Audio.appNodeDisplayName(node);
        return properties["application.name"] || node.description || node.name || "";
    }

    /** The programs capturing now, each { key, name, kind }, one a program and kind. */
    readonly property var users: {
        const seen = ({});
        const list = [];
        for (const capturer of root.screenTakers) {
            const key = `screen:${capturer.name}`;
            if (seen[key])
                continue;
            seen[key] = true;
            list.push({ key: key, name: capturer.name, kind: "screen" });
        }
        for (const node of root.consumers) {
            const properties = node.properties ?? {};
            let linked = false;
            let fromOutput = false;
            let fromScreen = false;
            for (const group of Pipewire.linkGroups?.values ?? []) {
                const source = group.source;
                if (group.target !== node || !source)
                    continue;
                linked = true;
                fromOutput = fromOutput || source.isSink;
                fromScreen = fromScreen || (source.name ?? "").startsWith("xdph") || (source.properties?.["media.class"] ?? "").startsWith("Stream/Output/Video");
            }
            const kind = root.kindOf(properties["media.class"] ?? "", properties["application.process.binary"] ?? "", node.name ?? "", linked, fromOutput, fromScreen);
            if (kind.length === 0)
                continue;
            const name = root.displayName(node);
            const key = `${kind}:${name}`;
            if (seen[key])
                continue;
            seen[key] = true;
            list.push({ key: key, name: name, kind: kind });
        }
        return list;
    }

    // -- What the compositor says, through the capture-report plugin -----------

    /** Every program the plugin last named as taking the screen: { pid, name, type, target }. */
    property var capturers: []
    /** Those of them that count, once they have gone on a moment. */
    property var screenTakers: []

    /**
     * Those to show of what the plugin named. The shell itself is left out,
     * its pictures of windows taken the same way, and the portal, which takes
     * the screen for a program PipeWire names, and the recording the shell
     * started, which has its own mark.
     */
    function counted(list) {
        return list.filter(capturer => capturer.pid !== Quickshell.processId
            && !capturer.name.startsWith("xdg-desktop-por")
            && !(root.recording && capturer.pid === root.recorderPid));
    }

    // A screenshot takes the screen for a moment, and showing it would only
    // blink. A program is shown once it has taken it for a second, and goes
    // as soon as it stops.
    onCapturersChanged: {
        const now = root.counted(root.capturers);
        root.screenTakers = root.screenTakers.filter(taker => now.some(capturer => capturer.pid === taker.pid));
        if (now.some(capturer => !root.screenTakers.some(taker => taker.pid === capturer.pid)))
            takersSettle.restart();
    }
    Timer {
        id: takersSettle
        interval: 1000
        onTriggered: root.screenTakers = root.counted(root.capturers)
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "capturers")
                return;
            try {
                const list = JSON.parse(event.data);
                root.capturers = Array.isArray(list) ? list : [];
            } catch (error) {
                root.capturers = [];
            }
        }
    }

    // -- The shell's own screen recording ---------------------------------------

    /** Where the recorder notes its process, as scripts/videos/record.sh does. */
    readonly property string pidFile: `${Quickshell.env("YUKI_RUNTIME_DIR") || Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/yuki-recorder.pid`
    property bool recording: false
    /** The recorder's process while it records, to tell it from the programs the plugin names. */
    property int recorderPid: 0
    /** When the recording was first seen, for how long it has run. */
    property real recordingSince: 0

    onRecordingChanged: root.recordingSince = root.recording ? Date.now() : 0

    function stopRecording() {
        Quickshell.execDetached(["bash", FileUtils.trimFileProtocol(Directories.recordScriptPath)]);
        recheckSoon.restart();
    }

    /** Looks again, a moment from now. */
    function recheck() {
        recheckSoon.restart();
    }

    // Looked at as the shell starts, and whenever the compositor says the
    // screen began or stopped being taken, which a recording starting or
    // stopping does: nothing is asked while nothing happens.
    Component.onCompleted: {
        recordingCheck.running = true;
        // What the plugin knows now, for a shell started while something
        // takes the screen. Nothing when the plugin is not there.
        Quickshell.execDetached(["hyprctl", "eval", "if hl.plugin.capture_report then hl.plugin.capture_report.announce() end"]);
    }
    Timer {
        id: recheckSoon
        interval: 300
        onTriggered: {
            recordingCheck.running = false;
            recordingCheck.running = true;
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "screencast")
                recheckSoon.restart();
        }
    }
    Process {
        id: recordingCheck
        command: ["sh", "-c", "[ -s \"$1\" ] && p=$(cat \"$1\") && kill -0 \"$p\" 2>/dev/null && echo \"$p\"", "yuki-recording", root.pidFile]
        stdout: StdioCollector {
            id: recordingOutput
            onStreamFinished: root.recorderPid = parseInt(recordingOutput.text.trim(), 10) || 0
        }
        onExited: exitCode => root.recording = exitCode === 0
    }
}
