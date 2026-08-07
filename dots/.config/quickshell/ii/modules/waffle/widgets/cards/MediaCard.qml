pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

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
            visible: !root.hasPlayer
            text: Translation.tr("Nothing is playing")
            color: Looks.colors.subfg
        }

        WText {
            Layout.fillWidth: true
            visible: root.hasPlayer
            text: MprisController.activePlayer?.trackTitle || Translation.tr("Unknown track")
            color: root.foregroundColor
            font.pixelSize: Looks.font.pixelSize.larger
            font.weight: Looks.font.weight.strong
            elide: Text.ElideRight
        }

        WText {
            Layout.fillWidth: true
            visible: root.hasPlayer && (MprisController.activePlayer?.trackArtist ?? "").length > 0
            text: MprisController.activePlayer?.trackArtist ?? ""
            color: ColorUtils.transparentize(root.foregroundColor, 0.3)
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Math.round(BoardLooks.unit * 0.4)
            visible: root.hasPlayer
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
            Item {
                Layout.fillWidth: true
            }
        }
    }

    component Control: WPanelIconButton {
        implicitWidth: Math.round(BoardLooks.controlSize * 1.4)
        implicitHeight: Math.round(BoardLooks.controlSize * 1.4)
        iconSize: Math.round(BoardLooks.controlSize * 0.7)
    }
}
