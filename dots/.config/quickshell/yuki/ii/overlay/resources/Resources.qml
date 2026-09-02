pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.ii.overlay
import qs.common

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 200
    /**
     * What the tabs are, and nothing that moves.
     *
     * The readings used to sit in here beside the names, so a list of three
     * objects was rebuilt on every poll and every tab button rebuilt its icon and
     * its label along with it, once a tick, for a reading only one of them shows.
     * The readings are looked up for whichever tab is open instead.
     */
    readonly property var resources: [
        { "icon": "planner_review", "name": Translation.tr("CPU") },
        { "icon": "memory", "name": Translation.tr("RAM") },
        { "icon": "swap_horiz", "name": Translation.tr("Swap") },
    ]

    function historyFor(index) {
        if (index === 1) return ResourceUsage.memoryUsageHistory;
        if (index === 2) return ResourceUsage.swapUsageHistory;
        return ResourceUsage.cpuUsageHistory;
    }

    function maxAvailableFor(index) {
        if (index === 1) return ResourceUsage.maxAvailableMemoryString;
        if (index === 2) return ResourceUsage.maxAvailableSwapString;
        return ResourceUsage.maxAvailableCpuString;
    }

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 4
        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.resources.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.resources.tabIndex = tabBar.currentIndex;
                    // Clicking a tab writes the index and drops the binding, so
                    // the tab stops following the saved state. The value just
                    // written is the one the binding gives back.
                    tabBar.currentIndex = Qt.binding(() => Persistent.states.overlay.resources.tabIndex);
                }

                Repeater {
                    model: root.resources.length
                    delegate: SecondaryTabButton {
                        required property int index
                        property var modelData: root.resources[index]
                        buttonIcon: modelData.icon
                        buttonText: modelData.name
                    }
                }
            }

            ResourceSummary {
                Layout.margins: 8
                history: root.historyFor(tabBar.currentIndex)
                maxAvailableString: root.maxAvailableFor(tabBar.currentIndex)
            }
        }
    }

    component ResourceSummary: RowLayout {
        id: resourceSummary
        required property list<real> history
        required property string maxAvailableString
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        ColumnLayout {
            spacing: 2
            StyledText {
                // Nothing read yet is not nought per cent, and multiplying the
                // end of an empty history put a NaN on screen until the first
                // reading landed.
                text: resourceSummary.history.length > 0
                    ? (resourceSummary.history[resourceSummary.history.length - 1] * 100).toFixed(1) + "%"
                    : "--"
                font {
                    family: Appearance.font.family.numbers
                    variableAxes: Appearance.font.variableAxes.numbers
                    pixelSize: Appearance.font.pixelSize.huge
                }
            }
            StyledText {
                text: Translation.tr("of %1").arg(resourceSummary.maxAvailableString)
                font {
                    // family: Appearance.font.family.numbers
                    // variableAxes: Appearance.font.variableAxes.numbers
                    pixelSize: Appearance.font.pixelSize.smallie
                }
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillHeight: true
            }
        }
        Rectangle {
            id: graphBg
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: graphBg.width
                    height: graphBg.height
                    radius: graphBg.radius
                }
            }
            Graph {
                anchors.fill: parent
                values: root.historyFor(tabBar.currentIndex)
                points: ResourceUsage.historyLength
                alignment: Graph.Alignment.Right
            }
        }
    }
}
