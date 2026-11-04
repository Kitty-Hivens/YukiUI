pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

import qs.core.services
import qs.blueberry.looks

// Where sound goes and comes from, how loud, and what each application plays
// through. Devices, volumes and mutes come live from PipeWire. Sockets, card
// profiles and moving an application go through AudioRouting.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var outputs: Audio.hardwareDevices(true)
    readonly property var inputs: Audio.hardwareDevices(false)
    readonly property var playing: Audio.outputAppNodes
    readonly property var recording: Audio.inputAppNodes
    readonly property var processors: Audio.virtualDevices(true).concat(Audio.virtualDevices(false))

    /**
     * The devices' volumes and the cards' sockets have been read, so the page
     * comes in whole rather than with its sliders at nought and its socket
     * lists missing for a moment.
     */
    readonly property bool ready: AudioRouting.loaded
        && [...root.outputs, ...root.inputs, ...root.playing, ...root.recording].every(node => node.ready)

    // Cards, sockets and the names behind streams are only read while shown.
    Component.onCompleted: {
        AudioRouting.subscribers++;
        StreamApps.subscribers++;
    }
    Component.onDestruction: {
        AudioRouting.subscribers--;
        StreamApps.subscribers--;
    }

    // Without this the volume of a device nobody plays to is never delivered.
    PwObjectTracker {
        objects: [...root.outputs, ...root.inputs, ...root.playing, ...root.recording]
    }

    spacing: ExLooks.settings.groupGap

    // A device: which it is, the socket it uses when it has several, and
    // whether new sound goes to it. A click on it makes it the one.
    component DeviceCard: SettingsCard {
        id: device

        required property var node
        required property bool isDefault
        readonly property var ports: AudioRouting.portsFor(device.node)

        signal chosen

        Layout.fillWidth: true
        glyph: device.node?.isSink ? "speaker" : "mic"
        text: Audio.friendlyDeviceName(device.node)
        description: device.isDefault ? Translation.tr("In use") : (device.node?.description ?? "")
        leads: false

        SettingsDropdown {
            visible: device.ports.length > 1
            anchors.verticalCenter: parent.verticalCenter
            model: device.ports.map(port => port.available ? port.description : `${port.description} (${Translation.tr("not plugged in")})`)
            currentIndex: device.ports.findIndex(port => port.name === AudioRouting.activePortFor(device.node))
            onActivated: index => AudioRouting.setPort(device.node, device.ports[index].name)
        }
        ExButton {
            anchors.verticalCenter: parent.verticalCenter
            kind: "flat"
            glyph: device.isDefault ? "radio_button_checked" : "radio_button_unchecked"
            enabled: !device.isDefault
            opacity: 1
            onClicked: device.chosen()
        }
    }

    // How loud, and muted or not.
    component VolumeCard: SettingsCard {
        id: volume

        required property var node
        property real maximum: 1
        property bool device: true

        readonly property bool muted: volume.node?.audio?.muted ?? false

        Layout.fillWidth: true
        leads: false

        ExButton {
            anchors.verticalCenter: parent.verticalCenter
            kind: "flat"
            glyph: volume.node?.isSink ? (volume.muted ? "volume_off" : "volume_up") : (volume.muted ? "mic_off" : "mic")
            onClicked: {
                if (volume.node?.audio)
                    volume.node.audio.muted = !volume.node.audio.muted;
            }
        }
        ExSlider {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 240
            from: 0
            to: volume.maximum
            value: volume.node?.audio?.volume ?? 0
            onMoved: {
                if (!volume.node?.audio)
                    return;
                if (volume.device)
                    Audio.setDeviceVolume(volume.node, value);
                else
                    volume.node.audio.volume = value;
            }
        }
        ExText {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round((volume.node?.audio?.volume ?? 0) * 100)}%`
            dim: true
        }
    }

    // An application: how loud, and what it plays through.
    component StreamCard: SettingsCard {
        id: stream

        required property var node
        readonly property var targets: Audio.virtualDevices(stream.node?.isSink ?? true).concat(Audio.hardwareDevices(stream.node?.isSink ?? true))
        readonly property var current: Audio.deviceOfStream(stream.node)
        readonly property bool muted: stream.node?.audio?.muted ?? false

        Layout.fillWidth: true
        leads: false
        text: Audio.appNodeDisplayName(stream.node)
        description: Audio.appNodeContext(stream.node)

        SettingsDropdown {
            visible: stream.targets.length > 1
            anchors.verticalCenter: parent.verticalCenter
            model: stream.targets.map(target => Audio.isHardware(target) ? Audio.friendlyDeviceName(target) : Translation.tr("Through %1").arg(Audio.friendlyDeviceName(target)))
            currentIndex: stream.targets.findIndex(target => target.id === stream.current?.id)
            onActivated: index => Audio.sendStreamTo(stream.node, stream.targets[index])
        }
        ExButton {
            anchors.verticalCenter: parent.verticalCenter
            kind: "flat"
            onClicked: {
                if (stream.node?.audio)
                    stream.node.audio.muted = !stream.node.audio.muted;
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 20
                opacity: stream.muted ? 0.35 : 1
                source: {
                    const own = StreamApps.iconFor(stream.node);
                    if (AppSearch.iconExists(own))
                        return Quickshell.iconPath(own, "image-missing");
                    return Quickshell.iconPath(AppSearch.guessIcon(stream.node?.properties["application.icon-name"] ?? stream.node?.properties["node.name"] ?? ""), "image-missing");
                }
            }
        }
        // Above a hundred for an application, not for a device: quiet source
        // material is the application's problem, a card pushed past its
        // ceiling is how speakers start distorting.
        ExSlider {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 200
            from: 0
            to: 1.5
            value: stream.node?.audio?.volume ?? 0
            onMoved: {
                if (stream.node?.audio)
                    stream.node.audio.volume = value;
            }
        }
        ExText {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round((stream.node?.audio?.volume ?? 0) * 100)}%`
            dim: true
        }
    }

    component Empty: ExText {
        Layout.fillWidth: true
        Layout.leftMargin: ExLooks.spacing.l
        dim: true
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Output")

        Repeater {
            model: root.outputs

            DeviceCard {
                required property var modelData
                node: modelData
                // Against the hardware the default reaches, so a processor
                // holding the default still marks the device it plays out of.
                isDefault: modelData?.id === Audio.defaultSinkEndpoint?.id
                onChosen: Audio.setDefaultSink(modelData)
            }
        }
        Empty {
            visible: root.outputs.length === 0
            text: Translation.tr("Nothing to play through")
        }
        VolumeCard {
            visible: Audio.sink !== null
            node: Audio.sink
            glyph: "tune"
            text: Translation.tr("Volume")
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Input")

        Repeater {
            model: root.inputs

            DeviceCard {
                required property var modelData
                node: modelData
                isDefault: modelData?.id === Audio.defaultSourceEndpoint?.id
                onChosen: Audio.setDefaultSource(modelData)
            }
        }
        Empty {
            visible: root.inputs.length === 0
            text: Translation.tr("Nothing to record from")
        }
        VolumeCard {
            visible: Audio.source !== null
            node: Audio.source
            glyph: "tune"
            text: Translation.tr("Volume")
        }
    }

    // Not devices: these answer "through what" rather than "out of what".
    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Processing")
        visible: root.processors.length > 0

        Repeater {
            model: root.processors

            SettingsCard {
                required property var modelData
                readonly property var endpoint: Audio.endpointOf(modelData)

                Layout.fillWidth: true
                glyph: "graphic_eq"
                text: Audio.friendlyDeviceName(modelData)
                description: Audio.managedByProcessor(modelData)
                    ? (endpoint ? Translation.tr("Applications play through it into %1").arg(Audio.friendlyDeviceName(endpoint)) : Translation.tr("Applications play through it"))
                    : Translation.tr("Created by a program rather than by hardware")
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Applications")

        Repeater {
            model: [...root.playing, ...root.recording]

            StreamCard {
                required property var modelData
                node: modelData
            }
        }
        Empty {
            visible: root.playing.length === 0 && root.recording.length === 0
            text: Translation.tr("Nothing is playing")
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Hardware")
        visible: AudioRouting.cards.length > 0

        Repeater {
            model: AudioRouting.cards

            SettingsCard {
                id: card

                required property var modelData
                readonly property var profiles: card.modelData.profiles

                Layout.fillWidth: true
                glyph: "memory"
                text: card.modelData.description
                description: Translation.tr("Which inputs and outputs the card offers")

                SettingsDropdown {
                    anchors.verticalCenter: parent.verticalCenter
                    model: card.profiles.map(profile => profile.available ? profile.description : `${profile.description} (${Translation.tr("not plugged in")})`)
                    currentIndex: card.profiles.findIndex(profile => profile.name === card.modelData.activeProfile)
                    onActivated: index => AudioRouting.setCardProfile(card.modelData.name, card.profiles[index].name)
                }
            }
        }
    }
}
