pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// How hard the machine is working, as Windows lays it out: the readings in a
// column, and the one picked drawn large beside them, over the last while.
//
// The graphics card is shown by how busy it is where the driver says so, and
// otherwise by its clock against the fastest it goes, which is what Intel's
// drivers give. A card that says neither is left out. How many frames a game
// draws is the game's to say, through an overlay inside it, and the shell
// cannot see it.
RowLayout {
    id: root

    /** The widget is on screen, and the card is read only then. */
    property bool watching: false

    // Counted in once and out once. The widget turns visible while it is
    // still being built, so a change and the completion both arrive for it.
    property bool counted: false
    function count() {
        if (root.watching === root.counted)
            return;
        root.counted = root.watching;
        ResourceUsage.gpuWatchers += root.counted ? 1 : -1;
    }
    onWatchingChanged: root.count()
    Component.onCompleted: root.count()
    Component.onDestruction: {
        if (root.counted)
            ResourceUsage.gpuWatchers--;
    }

    function percent(value: real): string {
        return `${Math.round(value * 100)}%`;
    }

    readonly property var readings: {
        const list = [{
            key: "cpu",
            name: Translation.tr("CPU"),
            value: ResourceUsage.cpuReady ? root.percent(ResourceUsage.cpuUsage) : "--",
            detail: ResourceUsage.maxAvailableCpuString.length > 0 && ResourceUsage.maxAvailableCpuString !== "--"
                ? Translation.tr("Up to %1").arg(ResourceUsage.maxAvailableCpuString) : "",
            history: ResourceUsage.cpuUsageHistory
        }];
        if (ResourceUsage.gpuKind === "busy")
            list.push({
                key: "gpu",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? root.percent(ResourceUsage.gpuUsage) : "--",
                detail: "",
                history: ResourceUsage.gpuUsageHistory
            });
        else if (ResourceUsage.gpuKind === "clock")
            list.push({
                key: "gpu",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? `${Math.round(ResourceUsage.gpuClock)} MHz` : "--",
                detail: Translation.tr("Clock, of %1 MHz").arg(Math.round(ResourceUsage.gpuMaxClock)),
                history: ResourceUsage.gpuUsageHistory
            });
        list.push({
            key: "ram",
            name: Translation.tr("RAM"),
            value: ResourceUsage.ready ? root.percent(ResourceUsage.memoryUsedPercentage) : "--",
            detail: ResourceUsage.ready
                ? Translation.tr("%1 of %2").arg(ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)).arg(ResourceUsage.maxAvailableMemoryString) : "",
            history: ResourceUsage.memoryUsageHistory
        });
        return list;
    }
    readonly property var shown: root.readings.find(reading => reading.key === Persistent.states.gameBar.performanceShown) ?? root.readings[0]

    spacing: ExLooks.spacing.m

    ColumnLayout {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: 130
        spacing: ExLooks.spacing.xs

        Repeater {
            model: root.readings

            AbstractButton {
                id: row

                required property var modelData
                readonly property bool picked: row.modelData.key === root.shown.key

                ExPrimaryOnly {
                    z: 1
                }

                Layout.fillWidth: true
                implicitHeight: 44
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: Persistent.states.gameBar.performanceShown = row.modelData.key

                background: Rectangle {
                    radius: ExLooks.radius.menuItem
                    color: row.picked ? ExLooks.colors.tonal : "transparent"

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: row.hovered
                        pressed: row.down
                    }
                }
                contentItem: Item {
                    ColumnLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        x: ExLooks.spacing.s
                        width: parent.width - 2 * ExLooks.spacing.s
                        spacing: 0

                        ExText {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            role: "caption"
                            color: row.picked ? ExLooks.colors.tonalInk : ExLooks.colors.textDim
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: row.modelData.value
                            role: "label"
                            color: row.picked ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 240
        spacing: ExLooks.spacing.xs

        RowLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.s

            ExText {
                text: root.shown.value
                role: "title"
                font.pixelSize: 26
                font.features: ({ "tnum": 1 })
            }
            ExText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: 4
                text: root.shown.detail
                role: "caption"
                dim: true
            }
        }
        ExGameBarGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 110
            values: root.shown.history
            points: ResourceUsage.historyLength
        }
    }
}
