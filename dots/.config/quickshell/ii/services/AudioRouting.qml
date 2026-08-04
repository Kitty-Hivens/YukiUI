pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Cards and their profiles, device ports, and where a stream is sent.
 *
 * Quickshell's PipeWire binding covers nodes, volumes, mutes and the default
 * device, and everything it covers keeps coming from there. A card profile, a
 * port and a stream's target device are not in it, and those are read from
 * pactl, which pipewire-pulse answers.
 *
 * Nothing here reads streams or application names: pactl's JSON writer refuses
 * non-ASCII ("Invalid ASCII character") and an application name or a track
 * title is exactly where non-ASCII turns up. Names come from the binding.
 */
Singleton {
    id: root

    /**
     * A subscription and three processes per change is not something to run for
     * a shell that is only showing a volume icon, so whoever displays this
     * counts itself in and back out.
     */
    property int subscribers: 0
    readonly property bool watching: root.subscribers > 0

    property var cards: []
    // Device name -> { activePort, ports }. Kept keyed by name because that is
    // what both pactl and the binding's nodes agree on.
    property var sinkPorts: ({})
    property var sourcePorts: ({})

    function portsFor(node) {
        if (!node)
            return [];
        return (node.isSink ? root.sinkPorts[node.name] : root.sourcePorts[node.name])?.ports ?? [];
    }

    function activePortFor(node) {
        if (!node)
            return "";
        return (node.isSink ? root.sinkPorts[node.name] : root.sourcePorts[node.name])?.activePort ?? "";
    }

    function setCardProfile(cardName, profileName) {
        root.run(["set-card-profile", cardName, profileName]);
    }

    function setPort(node, portName) {
        if (!node)
            return;
        root.run([node.isSink ? "set-sink-port" : "set-source-port", node.name, portName]);
    }

    /**
     * Sends one application's audio to a different device.
     *
     * Addressed by object.serial because that is the number pactl prints as a
     * stream's index; the binding's own id is the PipeWire object id, which
     * pactl does not take.
     */
    function moveStream(stream, device) {
        const serial = stream?.properties?.["object.serial"] ?? "";
        if (serial.length === 0 || !device)
            return false;
        root.run([stream.isSink ? "move-sink-input" : "move-source-output", serial, device.name]);
        return true;
    }

    function run(args) {
        commandProc.command = ["pactl"].concat(args);
        commandProc.running = true;
        // pactl answers the request before pipewire-pulse has announced the
        // result, and the subscription reports it a moment later. Asking again
        // shortly after covers the case where it does not.
        reloadTimer.restart();
    }

    function reload() {
        readProc.running = true;
    }

    Process {
        id: commandProc
        stderr: StdioCollector {
            id: commandError
            onStreamFinished: {
                if (commandError.text.trim().length > 0)
                    console.log("[AudioRouting]", commandError.text.trim());
            }
        }
    }

    // One process rather than three: the three lists are read together and
    // parsed together, so the model never shows a card from one moment and a
    // port from another.
    Process {
        id: readProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // Each list falls back to an empty one of its own. Substituted straight
        // into the object, a single list pactl refused to write left the whole
        // thing unparseable and blanked the other two along with it.
        command: ["bash", "-c",
            `cards=$(pactl -f json list cards 2>/dev/null); `
            + `sinks=$(pactl -f json list sinks 2>/dev/null); `
            + `sources=$(pactl -f json list sources 2>/dev/null); `
            + `printf '{"cards":%s,"sinks":%s,"sources":%s}' "\${cards:-[]}" "\${sinks:-[]}" "\${sources:-[]}"`]
        stdout: StdioCollector {
            id: readCollector
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(readCollector.text);
                } catch (error) {
                    // A mangled read is not a reason to blank out a page that
                    // was showing correct values a second ago.
                    console.log("[AudioRouting] could not read the device list:", error);
                    return;
                }
                root.cards = (parsed.cards ?? []).map(card => ({
                    name: card.name,
                    description: card.properties?.["device.description"] ?? card.name,
                    activeProfile: card.active_profile ?? "",
                    profiles: Object.keys(card.profiles ?? {}).map(name => ({
                        name: name,
                        description: card.profiles[name].description ?? name,
                        // Reported as unavailable when the socket has nothing
                        // plugged into it, and offering it anyway produces a
                        // profile switch that silently does nothing.
                        available: card.profiles[name].available !== "no"
                    }))
                }));
                root.sinkPorts = root.portMap(parsed.sinks);
                root.sourcePorts = root.portMap(parsed.sources);
            }
        }
    }

    function portMap(devices) {
        const map = ({});
        for (const device of devices ?? []) {
            map[device.name] = {
                activePort: device.active_port ?? "",
                ports: (device.ports ?? []).map(port => ({
                    name: port.name,
                    description: port.description ?? port.name,
                    available: port.availability !== "not available"
                }))
            };
        }
        return map;
    }

    // Reports every change the server makes, including the ones this service
    // asked for, so the model follows the system rather than assuming its own
    // commands landed.
    Process {
        id: subscribeProc
        running: root.watching
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                // Streams change constantly while audio plays and carry nothing
                // this service reads, so sink-input and source-output events are
                // left out rather than re-reading the card list per frame.
                if (/on (card|sink|source|server) #/.test(line))
                    reloadTimer.restart();
            }
        }
    }

    Timer {
        id: reloadTimer
        interval: 200
        onTriggered: root.reload()
    }

    onWatchingChanged: {
        if (root.watching)
            root.reload();
    }
}
