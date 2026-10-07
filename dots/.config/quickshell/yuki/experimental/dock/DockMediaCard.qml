pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core.functions
import qs.core.services
import qs.experimental.looks

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

    // The player says where it is only when asked, so it is asked once a second
    // while the track runs and someone can see it.
    Timer {
        running: root.active && root.shown && (root.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player?.positionChanged()
    }
    /** How far the track has got, from 0 to 1, or -1 when the player does not say how long it is. */
    readonly property real progress: (root.player?.lengthSupported ?? false) && root.player.length > 0
        ? Math.max(0, Math.min(1, root.player.position / root.player.length)) : -1

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
            Layout.fillWidth: true
            spacing: ExLooks.spacing.m

            ClippingRectangle {
                implicitWidth: 56
                implicitHeight: 56
                radius: ExLooks.radius.menuItem
                color: ExLooks.colors.control

                ExGlyph {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "music_note"
                    size: 24
                    color: ExLooks.colors.textDim
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: MprisController.activeTrack?.artUrl || ""
                    sourceSize: Qt.size(112, 112)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
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

        // How far the track has got.
        Item {
            Layout.fillWidth: true
            implicitHeight: 3
            visible: root.progress >= 0

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: ExLooks.colors.border
            }
            Rectangle {
                width: parent.width * Math.max(0, root.progress)
                height: parent.height
                radius: height / 2
                color: ExLooks.colors.accent
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
                readonly property bool playing: root.player?.isPlaying ?? false
                kind: "tonal"
                glyph: playing ? "pause" : "play_arrow"
                enabled: playing ? (root.player?.canPause ?? false) : (root.player?.canPlay ?? false)
                onClicked: root.player?.togglePlaying()
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
