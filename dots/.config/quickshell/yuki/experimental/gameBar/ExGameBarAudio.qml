pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

import qs.core.services
import qs.experimental
import qs.experimental.looks

// How loud: the sound that comes out and the microphone, each a glyph and a
// slider as in quick settings, and every program playing on a card under
// them, each muted by its icon. Which device sound goes to is chosen in the
// settings.
ColumnLayout {
    id: root

    readonly property var playing: Audio.outputAppNodes

    Layout.fillWidth: true
    spacing: ExLooks.spacing.s

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
            onClicked: {
                if (level.node?.audio)
                    level.node.audio.muted = !level.node.audio.muted;
            }

            ExStatusGlyph {
                visible: level.status.length > 0
                anchors.centerIn: parent
                name: level.status
                size: 18
                color: level.muted ? ExLooks.colors.textDim : ExLooks.colors.accent
            }
            ExGlyph {
                visible: level.icon.length === 0 && level.status.length === 0
                anchors.centerIn: parent
                text: level.glyph
                size: 18
                color: level.muted ? ExLooks.colors.textDim : ExLooks.colors.accent
            }
            IconImage {
                visible: level.icon.length > 0
                anchors.centerIn: parent
                implicitSize: 22
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
    }

    Level {
        visible: Audio.sink !== null
        node: Audio.sink
        status: ExStatusGlyphs.volumeGlyph
    }
    Level {
        visible: Audio.source !== null
        node: Audio.source
        glyph: muted ? "mic_off" : "mic"
    }

    // The programs, on a card as quick settings sets off what is playing.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: ExLooks.spacing.xs
        implicitHeight: card.implicitHeight + 2 * ExLooks.spacing.m
        radius: ExLooks.radius.tile
        color: ExLooks.colors.glassSunken

        ColumnLayout {
            id: card

            x: ExLooks.spacing.m
            y: ExLooks.spacing.m
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.s

            ExText {
                Layout.fillWidth: true
                text: Translation.tr("Applications")
                role: "caption"
                dim: true
            }
            ExText {
                visible: root.playing.length === 0
                Layout.fillWidth: true
                text: Translation.tr("Nothing is playing")
                role: "label"
            }

            // As many as fit, and the rest scrolled to.
            Flickable {
                visible: root.playing.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.min(apps.implicitHeight, 240)
                contentHeight: apps.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: apps

                    width: parent.width
                    spacing: ExLooks.spacing.s

                    Repeater {
                        model: root.playing

                        ColumnLayout {
                            id: app

                            required property var modelData
                            readonly property string context: Audio.appNodeContext(app.modelData)

                            Layout.fillWidth: true
                            spacing: 0

                            // In line with the slider under it.
                            ExText {
                                Layout.fillWidth: true
                                Layout.leftMargin: ExLooks.sizes.control + ExLooks.spacing.s
                                text: app.context.length > 0 ? `${Audio.appNodeDisplayName(app.modelData)}: ${app.context}` : Audio.appNodeDisplayName(app.modelData)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                role: "label"
                            }
                            // Above a hundred for a program, not for a device:
                            // quiet material is the program's problem, a card
                            // pushed past its ceiling is how speakers start
                            // distorting.
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
    }
}
