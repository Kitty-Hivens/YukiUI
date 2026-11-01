pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// Taking the screen: a picture of all of it, a part of it through the
// snipping tool, or a video of it until stopped, with the sound that is
// playing or without. Tiles, as quick settings has them. Whatever takes the
// screen puts the bar away first, so the bar is not in the picture.
ColumnLayout {
    id: root

    /** The game bar, which does the taking. */
    required property var bar

    readonly property bool recording: CaptureWatch.recording

    Layout.fillWidth: true
    spacing: ExLooks.spacing.s

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

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: ExLooks.spacing.s
        rowSpacing: ExLooks.spacing.s

        ExToggleTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            checkable: false
            restFill: ExLooks.colors.glassControl
            glyph: "photo_camera"
            text: Translation.tr("Screenshot")
            subtitle: Translation.tr("Whole screen")
            onClicked: root.bar.screenshot()
        }
        ExToggleTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            checkable: false
            restFill: ExLooks.colors.glassControl
            glyph: "screenshot_region"
            text: Translation.tr("Region")
            subtitle: Translation.tr("Part of the screen")
            onClicked: root.bar.snip()
        }
        ExToggleTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            checkable: false
            restFill: ExLooks.colors.glassControl
            checked: root.recording
            glyph: root.recording ? "stop_circle" : "radio_button_checked"
            text: root.recording ? Translation.tr("Stop") : Translation.tr("Record")
            subtitle: root.recording ? root.elapsed() : Translation.tr("Whole screen")
            onClicked: {
                if (root.recording)
                    CaptureWatch.stopRecording();
                else
                    root.bar.startRecording();
            }
        }
        ExToggleTile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            checkable: false
            restFill: ExLooks.colors.glassControl
            checked: Persistent.states.gameBar.recordSound
            glyph: "graphic_eq"
            text: Translation.tr("Sound")
            subtitle: checked ? Translation.tr("On") : Translation.tr("Off")
            onClicked: Persistent.states.gameBar.recordSound = !Persistent.states.gameBar.recordSound
        }
    }

    // Its glyph in line with the tiles' glyphs, the plate reaching out past it.
    ExButton {
        Layout.alignment: Qt.AlignLeft
        Layout.topMargin: ExLooks.spacing.xs
        Layout.leftMargin: -ExLooks.sizes.buttonPadding + ExLooks.spacing.m + 2
        kind: "flat"
        glyph: "folder_open"
        text: Translation.tr("Open recordings")
        onClicked: root.bar.openRecordings()
    }
}
