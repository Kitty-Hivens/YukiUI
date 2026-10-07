pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

import qs.core.services
import qs.experimental
import qs.experimental.looks

// How loud: the sound that comes out, the microphone, and each program
// playing, muted by its icon. Which device sound goes to is chosen in the
// settings.
ColumnLayout {
    id: root

    readonly property var playing: Audio.outputAppNodes

    spacing: ExLooks.spacing.s
    Layout.preferredWidth: 320

    // The names and icons behind streams are only worked out while shown.
    Component.onCompleted: StreamApps.subscribers++
    Component.onDestruction: StreamApps.subscribers--

    // Without this the volume of a program is never delivered.
    PwObjectTracker {
        objects: [...root.playing]
    }

    // A volume: what it is for, muted by a click on it, and how loud.
    component Level: RowLayout {
        id: level

        required property var node
        property real maximum: 1
        property bool device: true
        property string glyph: ""
        /** A status glyph, by its name in ExStatusGlyphs, in place of the glyph. */
        property string status: ""
        property string icon: ""

        readonly property bool muted: level.node?.audio?.muted ?? false

        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        ExButton {
            kind: "flat"
            implicitWidth: 32
            implicitHeight: 32
            onClicked: {
                if (level.node?.audio)
                    level.node.audio.muted = !level.node.audio.muted;
            }

            ExStatusGlyph {
                visible: level.status.length > 0
                anchors.centerIn: parent
                name: level.status
                color: level.muted ? ExLooks.colors.textDim : ExLooks.colors.text
            }
            ExGlyph {
                visible: level.icon.length === 0 && level.status.length === 0
                anchors.centerIn: parent
                text: level.glyph
                size: 20
                color: level.muted ? ExLooks.colors.textDim : ExLooks.colors.text
            }
            IconImage {
                visible: level.icon.length > 0
                anchors.centerIn: parent
                implicitSize: 20
                opacity: level.muted ? 0.35 : 1
                source: level.icon
            }
        }
        ExSlider {
            Layout.fillWidth: true
            implicitWidth: 160
            from: 0
            to: level.maximum
            value: level.node?.audio?.volume ?? 0
            onMoved: {
                if (!level.node?.audio)
                    return;
                if (level.device)
                    Audio.setDeviceVolume(level.node, value);
                else
                    level.node.audio.volume = value;
            }
        }
        ExText {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: `${Math.round((level.node?.audio?.volume ?? 0) * 100)}%`
            role: "caption"
            dim: true
            font.features: ({ "tnum": 1 })
        }
    }

    component Heading: ExText {
        Layout.fillWidth: true
        Layout.topMargin: ExLooks.spacing.xs
        role: "caption"
        dim: true
    }

    Heading {
        visible: Audio.sink !== null
        text: Audio.friendlyDeviceName(Audio.defaultSinkEndpoint ?? Audio.sink)
    }
    Level {
        visible: Audio.sink !== null
        node: Audio.sink
        status: ExStatusGlyphs.volumeGlyph
    }

    Heading {
        visible: Audio.source !== null
        text: Audio.friendlyDeviceName(Audio.defaultSourceEndpoint ?? Audio.source)
    }
    Level {
        visible: Audio.source !== null
        node: Audio.source
        glyph: muted ? "mic_off" : "mic"
    }

    Heading {
        text: Translation.tr("Applications")
    }
    ExText {
        visible: root.playing.length === 0
        Layout.fillWidth: true
        text: Translation.tr("Nothing is playing")
        role: "label"
        dim: true
    }

    // As many as fit, and the rest scrolled to.
    Flickable {
        visible: root.playing.length > 0
        Layout.fillWidth: true
        implicitHeight: Math.min(apps.implicitHeight, 260)
        contentHeight: apps.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: apps

            width: parent.width
            spacing: ExLooks.spacing.xs

            Repeater {
                model: root.playing

                ColumnLayout {
                    id: app

                    required property var modelData
                    readonly property string context: Audio.appNodeContext(app.modelData)

                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        text: app.context.length > 0 ? `${Audio.appNodeDisplayName(app.modelData)}: ${app.context}` : Audio.appNodeDisplayName(app.modelData)
                        role: "caption"
                    }
                    // Above a hundred for a program, not for a device: quiet
                    // material is the program's problem, a card pushed past
                    // its ceiling is how speakers start distorting.
                    Level {
                        node: app.modelData
                        device: false
                        maximum: 1.5
                        icon: {
                            const own = StreamApps.iconFor(app.modelData);
                            if (AppSearch.iconExists(own))
                                return Quickshell.iconPath(own, "image-missing");
                            return Quickshell.iconPath(AppSearch.guessIcon(app.modelData?.properties["application.icon-name"] ?? app.modelData?.properties["node.name"] ?? ""), "image-missing");
                        }
                    }
                }
            }
        }
    }
}
