pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio.volume ?? 0
    
    function friendlyDeviceName(node) {
        // Callers ask about a device that may not be resolved yet, and a name is
        // wanted for the binding either way.
        return (node?.nickname || node?.description || Translation.tr("Unknown"));
    }
    /**
     * The program, not the runtime that happens to carry it.
     *
     * An Electron application reports itself as "Chromium", so the name of the
     * desktop entry behind the process wins when one was found. See
     * [StreamApps] -- it only looks while something is displaying the answer,
     * and falls back to what the stream says about itself.
     */
    function appNodeDisplayName(node) {
        return (StreamApps.nameFor(node) || node.properties["application.name"] || node.description || node.name)
    }

    // Names a stream gives itself when it has nothing to say: repeating them
    // after the application's name fills a line without adding to it.
    readonly property var uninformativeStreamNames: [/^playback( stream)?$/i, /^audio stream/i, /^simple dsp stream$/i, /^recording( stream)?$/i, /^capture$/i]

    /** What the application is playing, when it says something worth showing. */
    function appNodeContext(node) {
        const media = node?.properties?.["media.name"] ?? "";
        if (media.length === 0)
            return "";
        for (const pattern of root.uninformativeStreamNames) {
            if (pattern.test(media))
                return "";
        }
        return media;
    }

    /**
     * A device that exists because a processor put it there, not because it is
     * hardware.
     *
     * EasyEffects creates its own sink and source and decides itself which of
     * them is the default; picking one by hand fights that and ends with sound
     * going into a chain nobody is listening to. It stays listed, because it is
     * where applications actually play, but it is not offered as a choice.
     */
    function managedByProcessor(node) {
        return (node?.name ?? "").startsWith("easyeffects_");
    }

    /**
     * Whether a node is a piece of hardware rather than something a program
     * created. Hardware is announced by a device; a virtual sink has none.
     */
    function isHardware(node) {
        if ((node?.properties?.["device.id"] ?? "").length > 0)
            return true;
        // A node's properties only arrive once something tracks it, and this
        // question is asked before that -- a device left untracked would be
        // filed as virtual for as long as nobody looked at it. The driver's own
        // naming answers the same question and is there from the start.
        return /^(alsa|bluez)_(input|output)\./.test(node?.name ?? "");
    }

    /**
     * Where sound comes out. Only hardware belongs on this list: a processor's
     * sink answers "through what", which is a different question and does not
     * belong in the same menu as a pair of headphones.
     */
    function hardwareDevices(isSink) {
        return (isSink ? root.outputDevices : root.inputDevices).filter(node => root.isHardware(node));
    }

    /** Sinks and sources a program put there: processors, loopbacks, nulls. */
    function virtualDevices(isSink) {
        return (isSink ? root.outputDevices : root.inputDevices).filter(node => !root.isHardware(node));
    }

    /** Whether a processor sits between applications and the hardware. */
    readonly property bool processorInPath: root.outputDevices.some(node => root.managedByProcessor(node))

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    /**
     * The device one application is currently playing into, or recording from.
     *
     * Read from the links rather than from the default device: a stream can be
     * sent somewhere else, and after that the default says nothing about it.
     */
    function deviceOfStream(node) {
        if (!node)
            return null;
        const groups = Pipewire.linkGroups.values;
        if (node.isSink)
            return groups.find(group => group.source?.id === node.id)?.target ?? null;
        return groups.find(group => group.target?.id === node.id)?.source ?? null;
    }

    /**
     * The hardware at the end of the line, following the graph through whatever
     * a processor put in between.
     *
     * An application landing in a processor's sink is only half the answer:
     * what a person wants to know is which speakers it eventually comes out of,
     * and the links are the only place that says so. Followed against the flow
     * on the input side, where the hardware is what feeds the chain rather than
     * what it feeds.
     */
    function endpointOf(node) {
        const groups = Pipewire.linkGroups.values;
        const downstream = node?.isSink ?? true;
        let current = node;
        const seen = [];
        for (let step = 0; step < 8; step++) {
            if (!current)
                return null;
            if (root.isHardware(current))
                return current;
            seen.push(current.id);
            const next = downstream
                ? groups.find(group => group.source?.id === current.id && seen.indexOf(group.target?.id) === -1)?.target
                : groups.find(group => group.target?.id === current.id && seen.indexOf(group.source?.id) === -1)?.source;
            if (!next)
                return null;
            current = next;
        }
        return null;
    }

    /**
     * The hardware new sound actually reaches, which is not always the default
     * device: a processor made default hands it on, and "sound goes here" is a
     * statement about the far end of that, not about the chain's first link.
     */
    readonly property var defaultSinkEndpoint: root.endpointOf(Pipewire.defaultAudioSink)
    readonly property var defaultSourceEndpoint: root.endpointOf(Pipewire.defaultAudioSource)

    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    /**
     * Whether the binding's own volume write is likely to be dropped.
     *
     * The real condition is not this one. A node belonging to a card has its
     * volume written through the card's route, and that write is only made when
     * the route reports a volume step; a Bluetooth route reports none, so the
     * write is dropped while the value the binding hands back changes anyway.
     * The step is not visible from QML, so what is tested here is the name --
     * a stand-in that covers the case that was measured and nothing more. A
     * device that fails the same way under another name would not be caught,
     * and one named this way that works fine pays a redundant write.
     */
    function volumeNeedsRouting(node) {
        return !(node?.isStream ?? false) && (node?.name ?? "").startsWith("bluez_");
    }

    /**
     * Sets a device's volume by whichever path actually reaches pipewire.
     *
     * The binding is written either way, so the control answers under the
     * finger; where that write goes nowhere it is sent again through
     * [AudioRouting]. The server's own report lands a moment later and settles
     * the number, so the two cannot disagree for long.
     */
    function setDeviceVolume(node, volume) {
        if (!node?.audio)
            return;
        const clamped = Math.max(0, Math.min(1, volume));
        // Routed before the binding is written, not after: the walk starts from
        // where the device is now, and the binding stops holding that the moment
        // it is given the destination.
        if (root.volumeNeedsRouting(node))
            AudioRouting.setDeviceVolume(node, clamped);
        node.audio.volume = clamped;
    }

    // Controls
    function toggleMute() {
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    function incrementVolume() {
        const step = Audio.value < 0.1 ? 0.01 : 0.02;
        root.setDeviceVolume(Audio.sink, Audio.sink.audio.volume + step);
    }

    function decrementVolume() {
        const step = Audio.value < 0.1 ? 0.01 : 0.02;
        root.setDeviceVolume(Audio.sink, Audio.sink.audio.volume - step);
    }

    /**
     * Sends one application to a device of its own.
     *
     * Lives here so callers have a single place to reach for audio, even though
     * the move itself is one of the things the PipeWire binding cannot do.
     */
    // Moves waiting on an exclusion, oldest first, paired one to one with the
    // requests EasyEffects is working through. See the Connections below.
    property var pendingMoves: []

    function sendStreamTo(stream, device) {
        // Only EasyEffects claims streams back; another program's sink is just
        // a place to play into, and asking EasyEffects about it would hold the
        // move behind an exclusion list that has nothing to say.
        const heldByProcessor = root.managedByProcessor(root.deviceOfStream(stream));
        const targetIsProcessor = root.managedByProcessor(device);

        // A processor takes every stream it is allowed to take, so moving one
        // out of it only holds once it has been told to leave that application
        // alone. Putting it back means withdrawing that.
        if (targetIsProcessor || heldByProcessor) {
            root.pendingMoves = root.pendingMoves.concat([
                {
                    stream: stream,
                    device: device
                }
            ]);
            if (EasyEffects.setExcluded(stream, !targetIsProcessor))
                return true;
            root.pendingMoves = root.pendingMoves.slice(0, -1);
        }
        return AudioRouting.moveStream(stream, device);
    }

    // The move waits for the exclusion to be in place: done the other way round
    // the stream is back where it started before the list has been read. It is
    // made even when the list could not be written -- the processor then takes
    // the stream back the next time it starts, which is still more than a
    // choice that visibly does nothing.
    Connections {
        target: EasyEffects
        function onBlocklistSettled(ok) {
            const pending = root.pendingMoves[0];
            root.pendingMoves = root.pendingMoves.slice(1);
            if (pending)
                AudioRouting.moveStream(pending.stream, pending.device);
        }
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
