import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.common.widgets
import qs.ii.overlay
import qs.ii.sidebarRight.volumeMixer

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 380

    contentItem: OverlayBackground {
        radius: root.contentRadius
        property real padding: 6

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = tabBar.currentIndex;
                    // A tab writes its own index when it is clicked, which drops
                    // the binding above, and from then on the bar and the pages
                    // only agree by accident. Putting it back costs nothing: the
                    // saved index is the one just written.
                    tabBar.currentIndex = Qt.binding(() => Persistent.states.overlay.volumeMixer.tabIndex);
                }

                SecondaryTabButton {
                    buttonIcon: "media_output"
                    buttonText: Translation.tr("Output")
                }
                SecondaryTabButton {
                    buttonIcon: "mic"
                    buttonText: Translation.tr("Input")
                }
            }
            SwipeView {
                id: swipeView
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.volumeMixer.tabIndex = swipeView.currentIndex;
                    // Swiping writes the index the same way a tab click does.
                    swipeView.currentIndex = Qt.binding(() => Persistent.states.overlay.volumeMixer.tabIndex);
                }
                clip: true

                PaddedVolumeDialogContent { 
                    isSink: true 
                }
                PaddedVolumeDialogContent { 
                    isSink: false 
                }
            }
        }
    }

    component PaddedVolumeDialogContent: Item {
        id: paddedVolumeDialogContent
        property alias isSink: volDialogContent.isSink
        property real padding: 12
        implicitWidth: volDialogContent.implicitWidth + padding * 2
        implicitHeight: volDialogContent.implicitHeight + padding * 2

        VolumeDialogContent {
            id: volDialogContent
            anchors {
                fill: parent
                margins: paddedVolumeDialogContent.padding
            }
        }
    }
}
