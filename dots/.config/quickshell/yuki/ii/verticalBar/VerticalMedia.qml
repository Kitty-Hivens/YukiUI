import qs.core
import qs.common.widgets
import qs.core.services
import qs
import qs.core.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

import qs.ii.bar as Bar
import qs.common
import qs.ii

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    Layout.fillHeight: true
    implicitHeight: mediaCircProg.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    onPressed: (event) => {
        // Through the controller, which checks there is a player and that it takes the
        // command: this widget is on the bar whether anything is playing or not, so
        // these reached straight into nothing whenever the bus was empty.
        if (event.button === Qt.MiddleButton) {
            MprisController.togglePlaying();
        } else if (event.button === Qt.BackButton) {
            MprisController.previous();
        } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
            MprisController.next();
        } else if (event.button === Qt.LeftButton) {
            IiStates.mediaControlsOpen = !IiStates.mediaControlsOpen
        }
    }

    ClippedFilledCircularProgress {
        id: mediaCircProg
        anchors.centerIn: parent
        implicitSize: 20

        lineWidth: Appearance.rounding.unsharpen
        value: activePlayer?.position / activePlayer?.length
        colPrimary: Appearance.colors.colOnSecondaryContainer
        enableAnimation: false

        Item {
            anchors.centerIn: parent
            width: mediaCircProg.implicitSize
            height: mediaCircProg.implicitSize
            
            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: activePlayer?.isPlaying ? "pause" : "music_note"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }

    Bar.StyledPopup {
        hoverTarget: root
        active: IiStates.mediaControlsOpen ? false : root.containsMouse

        Column {
            anchors.centerIn: parent
            spacing: 4

            Bar.StyledPopupHeaderRow {
                icon: "music_note"
                label: Translation.tr("Media")
            }

            StyledText {
                color: Appearance.colors.colOnSurfaceVariant
                text: `${cleanedTitle}${activePlayer?.trackArtist ? '\n' + activePlayer.trackArtist : ''}`
            }
        }
    }

}
