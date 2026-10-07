pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// Taking the screen: a picture of all of it, a part of it through the
// snipping tool, or a video of it until stopped, with the sound that is
// playing or without. Whatever takes the screen puts the bar away first, so
// the bar is not in the picture.
ColumnLayout {
    id: root

    /** The game bar, which does the taking. */
    required property var bar

    readonly property bool recording: CaptureWatch.recording

    spacing: ExLooks.spacing.m
    Layout.preferredWidth: 320

    // A round button with what it does under it.
    component Action: AbstractButton {
        id: action

        ExPrimaryOnly {
            z: 1
        }

        property string glyph
        property bool accent: false

        Layout.fillWidth: true
        implicitHeight: plate.height + ExLooks.spacing.xs + caption.implicitHeight
        hoverEnabled: true
        focusPolicy: Qt.NoFocus

        background: Item {}
        contentItem: Item {
            Rectangle {
                id: plate

                anchors.horizontalCenter: parent.horizontalCenter
                width: 52
                height: 52
                radius: height / 2
                color: action.accent ? ExLooks.colors.accent : ExLooks.colors.control

                ExStateLayer {
                    ink: action.accent ? ExLooks.colors.accentInk : ExLooks.colors.controlInk
                    hovered: action.hovered
                    pressed: action.down
                }
                ExGlyph {
                    anchors.centerIn: parent
                    text: action.glyph
                    size: 24
                    fill: action.accent ? 1 : 0
                    color: action.accent ? ExLooks.colors.accentInk : ExLooks.colors.controlInk
                }
            }
            ExText {
                id: caption

                anchors.top: plate.bottom
                anchors.topMargin: ExLooks.spacing.xs
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: action.text
                role: "caption"
                dim: true
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        Action {
            glyph: "photo_camera"
            text: Translation.tr("Screenshot")
            onClicked: root.bar.screenshot()
        }
        Action {
            glyph: "screenshot_region"
            text: Translation.tr("Region")
            onClicked: root.bar.snip()
        }
        Action {
            glyph: root.recording ? "stop" : "radio_button_checked"
            text: root.recording ? Translation.tr("Stop") : Translation.tr("Record")
            accent: root.recording
            onClicked: {
                if (root.recording)
                    CaptureWatch.stopRecording();
                else
                    root.bar.startRecording();
            }
        }
    }

    // How long the recording has run, counted while it is shown.
    property real now: Date.now()
    Timer {
        running: root.recording && root.visible
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    function elapsed(): string {
        const seconds = Math.max(0, Math.floor((root.now - CaptureWatch.recordingSince) / 1000));
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor(seconds / 60) % 60;
        const rest = String(seconds % 60).padStart(2, "0");
        return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${rest}` : `${minutes}:${rest}`;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        Rectangle {
            visible: root.recording
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: ExLooks.colors.destructive
        }
        ExText {
            Layout.fillWidth: true
            text: root.recording ? Translation.tr("Recording, %1").arg(root.elapsed()) : Translation.tr("Not recording")
            role: "label"
            dim: !root.recording
            font.features: ({ "tnum": 1 })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        ExText {
            Layout.fillWidth: true
            text: Translation.tr("Record the sound playing")
            wrapMode: Text.Wrap
        }
        ExSwitch {
            checked: Persistent.states.gameBar.recordSound
            onToggled: Persistent.states.gameBar.recordSound = checked
        }
    }

    // Its glyph in line with the text above, the plate reaching out past it.
    ExButton {
        Layout.alignment: Qt.AlignLeft
        Layout.leftMargin: -ExLooks.sizes.buttonPadding + ExLooks.spacing.xs
        kind: "flat"
        glyph: "folder_open"
        text: Translation.tr("Open recordings")
        onClicked: root.bar.openRecordings()
    }
}
