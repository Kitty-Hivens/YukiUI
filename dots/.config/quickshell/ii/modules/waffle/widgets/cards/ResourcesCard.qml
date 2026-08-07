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

// What the machine is doing, read off the machine itself: /proc for the memory and
// the processor, one call to the filesystem for the disk. Nothing here leaves the
// machine and nothing is sampled that is not drawn.
WWidgetCard {
    id: root

    cardId: "resources"
    title: Translation.tr("Resources")
    iconName: "desktop"
    readout: `${Math.round(ResourceUsage.cpuUsage * 100)}%`

    // The filesystem costs a process to read, unlike /proc, so it is only read while
    // this card is on the board.
    Component.onCompleted: ResourceUsage.storagePolling = true
    Component.onDestruction: ResourceUsage.storagePolling = false

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: Math.round(BoardLooks.unit * 0.5)

        Reading {
            label: Translation.tr("Processor")
            fraction: ResourceUsage.cpuUsage
            value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
        }
        Reading {
            label: Translation.tr("Memory")
            fraction: ResourceUsage.memoryUsedPercentage
            value: `${ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)} / ${ResourceUsage.maxAvailableMemoryString}`
        }
        Reading {
            label: Translation.tr("Swap")
            visible: ResourceUsage.swapTotal > 1
            fraction: ResourceUsage.swapUsedPercentage
            value: `${ResourceUsage.kbToGbString(ResourceUsage.swapUsed)} / ${ResourceUsage.maxAvailableSwapString}`
        }
        Reading {
            label: Translation.tr("Disk")
            visible: ResourceUsage.storageTotal > 0
            fraction: ResourceUsage.storageUsedPercentage
            value: `${ResourceUsage.kbToGbString(ResourceUsage.storageUsed)} / ${ResourceUsage.kbToGbString(ResourceUsage.storageTotal)}`
        }
    }

    // A named line, a figure read in the monospace the board uses for readings, and
    // a rule under both showing how much of it is taken.
    component Reading: ColumnLayout {
        id: reading

        required property string label
        required property real fraction
        required property string value

        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            WText {
                text: reading.label
                color: ColorUtils.transparentize(root.foregroundColor, 0.25)
            }
            Item {
                Layout.fillWidth: true
            }
            WText {
                text: reading.value
                color: BoardLooks.readoutColor
                font.family: BoardLooks.readoutFamily
                font.pixelSize: BoardLooks.readoutSize
                font.letterSpacing: BoardLooks.readoutSpacing
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 2
            radius: 1
            color: BoardLooks.rule

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, reading.fraction))
                height: parent.height
                radius: parent.radius
                color: Looks.colors.accent

                Behavior on width {
                    animation: Looks.transition.move.createObject(this)
                }
            }
        }
    }
}
