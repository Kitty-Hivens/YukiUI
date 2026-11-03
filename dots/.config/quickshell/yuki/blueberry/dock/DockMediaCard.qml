pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// What is playing, at the top of quick settings, as Windows 11 shows it: the
// player, the picture, the track and who made it, how far it has got, and
// back, play or pause, and on. With more than one player, the next one is a
// click away. Shown only while a player has something to show.
Rectangle {
    id: root

    /** Quick settings is open: how far the track has got is asked only then. */
    property bool active: false

    readonly property var player: MprisController.activePlayer
    readonly property string title: StringUtils.cleanMusicTitle(root.player?.trackTitle ?? "")
    // A player that has gone quiet, a browser tab left on its last page say,
    // has nothing to show.
    readonly property bool shown: !!root.player && (root.title.length > 0 || (root.player?.isPlaying ?? false))
    readonly property var entry: DesktopEntries.byId(root.player?.desktopEntry ?? "")
    readonly property bool playing: root.player?.isPlaying ?? false

    // The player says where it is only when asked, so it is asked once a
    // second while someone can see it, paused or not: a track paused before
    // quick settings opened is shown where it stopped.
    Timer {
        running: root.active && root.shown
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }

    /** The track has a length and a place in it, so how far it has got can be shown. */
    readonly property bool timed: (root.player?.lengthSupported ?? false) && (root.player?.positionSupported ?? false) && root.player.length > 0
    /** And it can be moved through. */
    readonly property bool seekable: root.timed && (root.player?.canSeek ?? false)
    /** How far the track has got, from 0 to 1, or 0 when the player does not say. */
    readonly property real progress: root.timed ? Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0

    function clock(seconds: real): string {
        const whole = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(whole / 3600);
        const minutes = Math.floor(whole / 60) % 60;
        const rest = String(whole % 60).padStart(2, "0");
        return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${rest}` : `${minutes}:${rest}`;
    }

    // The bar moves on smoothly between readings while the track plays, and
    // jumps when it is moved, a new track starts or the player says otherwise.
    property real drawnProgress: 0
    onProgressChanged: {
        const step = root.progress - root.drawnProgress;
        if (root.playing && !seek.held && step > 0 && step < 0.05) {
            glide.to = root.progress;
            glide.restart();
        } else {
            glide.stop();
            root.drawnProgress = root.progress;
        }
    }
    NumberAnimation {
        id: glide
        target: root
        property: "drawnProgress"
        duration: 1000
    }

    // A new track, or another player, slides in from the side it came from.
    Connections {
        target: MprisController
        function onTrackChanged(reverse) {
            trackIn.from = reverse ? -16 : 16;
            trackIn.restart();
        }
    }
    // Faded in as it comes to have something to show.
    onShownChanged: {
        if (root.shown)
            appear.restart();
    }
    NumberAnimation {
        id: appear
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: ExLooks.motion.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.standard
    }

    implicitHeight: content.implicitHeight + 2 * ExLooks.spacing.m
    radius: ExLooks.radius.tile
    color: ExLooks.colors.surfaceSunken

    ColumnLayout {
        id: content

        x: ExLooks.spacing.m
        y: ExLooks.spacing.m
        width: parent.width - 2 * ExLooks.spacing.m
        spacing: ExLooks.spacing.s

        RowLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.s

            IconImage {
                visible: !!root.entry?.icon
                implicitSize: 16
                source: Quickshell.iconPath(root.entry?.icon ?? "", true)
            }
            ExGlyph {
                visible: !root.entry?.icon
                text: "music_note"
                size: 16
                color: ExLooks.colors.textDim
            }
            ExText {
                Layout.fillWidth: true
                text: root.entry?.name || root.player?.identity || Translation.tr("Media")
                role: "caption"
                dim: true
                elide: Text.ElideRight
            }
            // The next player, when there is more than one.
            ExButton {
                visible: MprisController.players.length > 1
                kind: "flat"
                implicitWidth: 28
                implicitHeight: 28
                glyph: "swap_horiz"
                onClicked: {
                    const players = MprisController.players;
                    const at = players.indexOf(root.player);
                    MprisController.setActivePlayer(players[(at + 1) % players.length]);
                }
            }
        }

        RowLayout {
            id: track

            property real shift: 0

            Layout.fillWidth: true
            spacing: ExLooks.spacing.m
            transform: Translate {
                x: track.shift
            }

            ParallelAnimation {
                id: trackIn

                property real from: 16

                NumberAnimation {
                    target: track
                    property: "shift"
                    from: trackIn.from
                    to: 0
                    duration: ExLooks.motion.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ExLooks.motion.decelerate
                }
                NumberAnimation {
                    target: track
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: ExLooks.motion.normal
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ExLooks.motion.standard
                }
            }

            ClippingRectangle {
                implicitWidth: 56
                implicitHeight: 56
                radius: ExLooks.radius.menuItem
                color: ExLooks.colors.control

                ExGlyph {
                    anchors.centerIn: parent
                    opacity: 1 - art.opacity
                    text: "music_note"
                    size: 24
                    color: ExLooks.colors.textDim
                }
                // Fades in once it has loaded, rather than popping in over
                // the note.
                Image {
                    id: art
                    anchors.fill: parent
                    source: MprisController.activeTrack?.artUrl || ""
                    sourceSize: Qt.size(112, 112)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: ExLooks.motion.normal }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ExText {
                    Layout.fillWidth: true
                    text: root.title || Translation.tr("Unknown Title")
                    role: "label"
                    font.weight: 600
                    elide: Text.ElideRight
                }
                ExText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist || ""
                    visible: text.length > 0
                    role: "caption"
                    dim: true
                    elide: Text.ElideRight
                }
            }
        }

        // How far the track has got, and moved through by a click or a drag
        // where the player allows it. Always there, empty for a player that
        // does not say, so the card does not change height when it starts to.
        Item {
            id: seek

            readonly property bool held: seekArea.pressed
            /** Where the bar is held, from 0 to 1. */
            property real heldAt: 0
            readonly property bool lit: seekArea.containsMouse || seekArea.pressed
            readonly property real drawn: seek.held ? seek.heldAt : root.drawnProgress

            Layout.fillWidth: true
            implicitHeight: 16

            Rectangle {
                id: groove

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: seek.lit && root.seekable ? 6 : 4
                radius: height / 2
                color: ExLooks.colors.border

                Behavior on height {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }

                Rectangle {
                    width: groove.width * seek.drawn
                    height: parent.height
                    radius: parent.radius
                    color: ExLooks.colors.accent
                    visible: root.timed
                }
            }
            Rectangle {
                visible: root.seekable
                x: groove.width * seek.drawn - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: ExLooks.colors.knob
                border.width: 1
                border.color: ExLooks.colors.knobEdge
                scale: seek.lit ? 1 : 0
                Behavior on scale {
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
            }
            MouseArea {
                id: seekArea

                anchors.fill: parent
                enabled: root.seekable
                hoverEnabled: true
                cursorShape: root.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: event => seek.heldAt = Math.max(0, Math.min(1, event.x / width))
                onPositionChanged: event => {
                    if (pressed)
                        seek.heldAt = Math.max(0, Math.min(1, event.x / width));
                }
                onReleased: {
                    if (!root.seekable)
                        return;
                    root.player.position = seek.heldAt * root.player.length;
                    root.drawnProgress = seek.heldAt;
                    glide.stop();
                    root.player.positionChanged();
                }
            }
        }

        // Where it is and how long it is, held as the bar is dragged.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: -ExLooks.spacing.xs
            spacing: ExLooks.spacing.s

            ExText {
                Layout.fillWidth: true
                text: root.timed ? root.clock((seek.held ? seek.heldAt * root.player.length : root.player.position)) : "--:--"
                role: "caption"
                dim: true
                font.features: ({ "tnum": 1 })
            }
            ExText {
                text: root.timed ? root.clock(root.player.length) : "--:--"
                role: "caption"
                dim: true
                font.features: ({ "tnum": 1 })
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: ExLooks.spacing.s

            ExButton {
                kind: "flat"
                glyph: "skip_previous"
                enabled: root.player?.canGoPrevious ?? false
                onClicked: root.player?.previous()
            }
            ExButton {
                id: playPause

                kind: "tonal"
                glyph: root.playing ? "pause" : "play_arrow"
                enabled: root.playing ? (root.player?.canPause ?? false) : (root.player?.canPlay ?? false)
                onClicked: root.player?.togglePlaying()
                // A small give as it turns from one to the other.
                onGlyphChanged: turn.restart()

                NumberAnimation {
                    id: turn
                    target: playPause
                    property: "scale"
                    from: 0.86
                    to: 1
                    duration: ExLooks.motion.normal
                    easing.type: Easing.OutBack
                }
            }
            ExButton {
                kind: "flat"
                glyph: "skip_next"
                enabled: root.player?.canGoNext ?? false
                onClicked: root.player?.next()
            }
        }
    }
}
