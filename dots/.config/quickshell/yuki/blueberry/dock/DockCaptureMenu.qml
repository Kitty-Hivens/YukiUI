pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks

// Who is capturing what, opened from the marks beside the keyboard layout: the
// screen recording the shell started, how long it has run and a way to stop
// it, and each program taking the screen, a camera, a microphone or the sound
// that is playing.
ExPopup {
    id: root

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    // Nothing left to show, nothing to stay open for.
    readonly property bool empty: !CaptureWatch.recording && CaptureWatch.users.length === 0
    onEmptyChanged: {
        if (root.empty)
            root.open = false;
    }

    /** Now, moved on every second the recording is shown. */
    property real now: Date.now()
    Timer {
        running: root.open && CaptureWatch.recording
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function elapsed(): string {
        const seconds = Math.max(0, Math.floor((root.now - CaptureWatch.recordingSince) / 1000));
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const two = value => String(value).padStart(2, "0");
        return hours > 0 ? `${hours}:${two(minutes % 60)}:${two(seconds % 60)}` : `${minutes}:${two(seconds % 60)}`;
    }

    function glyphFor(kind: string): string {
        return kind === "screen" ? "screen_share" : kind === "camera" ? "videocam" : kind === "microphone" ? "mic" : "graphic_eq";
    }

    function describe(kind: string): string {
        return kind === "screen" ? Translation.tr("Takes the screen")
            : kind === "camera" ? Translation.tr("Uses the camera")
            : kind === "microphone" ? Translation.tr("Uses the microphone")
            : Translation.tr("Records the sound playing");
    }

    component Row_: RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        Layout.leftMargin: ExLooks.spacing.s + 2
        Layout.rightMargin: ExLooks.spacing.s
        spacing: ExLooks.spacing.m
    }

    ColumnLayout {
        // Wider than a menu, for the recording's name beside its button.
        width: Math.max(ExLooks.sizes.menuWidth, 320)
        spacing: 0

        Row_ {
            visible: CaptureWatch.recording

            ExGlyph {
                text: "radio_button_checked"
                size: 18
                fill: 1
                color: ExLooks.colors.destructive
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                ExText {
                    Layout.fillWidth: true
                    text: Translation.tr("Screen recording")
                }
                ExText {
                    Layout.fillWidth: true
                    text: root.elapsed()
                    role: "caption"
                    dim: true
                    font.features: ({ "tnum": 1 })
                }
            }
            ExButton {
                kind: "accent"
                glyph: "stop"
                text: Translation.tr("Stop")
                onClicked: CaptureWatch.stopRecording()
            }
        }

        ExMenuSeparator {
            Layout.fillWidth: true
            visible: CaptureWatch.recording && CaptureWatch.users.length > 0
        }

        Repeater {
            model: CaptureWatch.users

            Row_ {
                id: user

                required property var modelData

                ExGlyph {
                    text: root.glyphFor(user.modelData.kind)
                    size: 18
                    color: ExLooks.colors.textDim
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: user.modelData.name
                        elide: Text.ElideRight
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: root.describe(user.modelData.kind)
                        role: "caption"
                        dim: true
                    }
                }
            }
        }
    }
}
