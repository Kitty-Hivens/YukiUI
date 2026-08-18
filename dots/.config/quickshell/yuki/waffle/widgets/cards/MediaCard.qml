pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import qs.waffle.widgets

// Whatever is playing, through MPRIS -- the same players the bar already talks to.
// The card asks the player and nothing else; there is no lookup of anything on the
// far side of the network to decorate a track with.
WWidgetCard {
    id: root

    cardId: "media"
    title: MprisController.activePlayer?.identity || Translation.tr("Media")
    iconName: "music-note-2"
    readout: MprisController.isPlaying ? Translation.tr("PLAYING") : ""

    readonly property bool hasPlayer: MprisController.activePlayer !== null

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: Math.round(BoardLooks.unit * 0.4)

        WText {
            Layout.fillWidth: true
            text: root.hasPlayer ? (MprisController.activePlayer?.trackTitle || Translation.tr("Unknown track")) : Translation.tr("Nothing is playing")
            color: root.hasPlayer ? root.foregroundColor : Looks.colors.subfg
            font.pixelSize: Looks.font.pixelSize.larger
            font.weight: Looks.font.weight.strong
            elide: Text.ElideRight
        }

        // Standing even when empty, so the card is the same height either way.
        WText {
            Layout.fillWidth: true
            text: root.hasPlayer ? (MprisController.activePlayer?.trackArtist ?? "") : ""
            color: ColorUtils.transparentize(root.foregroundColor, 0.3)
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Math.round(BoardLooks.unit * 0.4)
            spacing: 4

            Control {
                iconName: "previous"
                enabled: MprisController.canGoPrevious
                onClicked: MprisController.previous()
            }
            Control {
                iconName: MprisController.isPlaying ? "pause" : "play"
                enabled: MprisController.canTogglePlaying
                onClicked: MprisController.togglePlaying()
            }
            Control {
                iconName: "next"
                enabled: MprisController.canGoNext
                onClicked: MprisController.next()
            }
        }
    }

    component Control: WPanelIconButton {
        implicitWidth: Math.round(BoardLooks.controlSize * 1.4)
        implicitHeight: Math.round(BoardLooks.controlSize * 1.4)
        iconSize: Math.round(BoardLooks.controlSize * 0.7)
        opacity: enabled ? 1 : 0.35
    }
}
