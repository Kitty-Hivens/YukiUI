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
 * sound that is playing, or taking the screen through the portal, read from
 * PipeWire, which names the program; and whether the screen recording the
 * shell starts is running.
 *
 * A program taking the screen straight from the compositor rather than
 * through the portal is not named here: the compositor says the screen is
 * being taken, and not by whom, and the shell's own previews of windows take
 * it the same way.
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

    // -- The shell's own screen recording ---------------------------------------

    /** Where the recorder notes its process, as scripts/videos/record.sh does. */
    readonly property string pidFile: `${Quickshell.env("YUKI_RUNTIME_DIR") || Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/yuki-recorder.pid`
    property bool recording: false
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
    Component.onCompleted: recordingCheck.running = true
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
        command: ["sh", "-c", "[ -s \"$1\" ] && kill -0 \"$(cat \"$1\")\" 2>/dev/null", "yuki-recording", root.pidFile]
        onExited: exitCode => root.recording = exitCode === 0
    }
}
