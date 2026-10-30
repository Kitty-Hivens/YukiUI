pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// How hard the machine is working: a tile for each reading, and the one
// picked drawn large under them over the last while, on a card as quick
// settings sets off what is playing.
//
// The graphics card is shown by how busy it is where the driver says so, and
// otherwise by its clock against the fastest it goes, which is what Intel's
// drivers give. A card that says neither is left out. How many frames a game
// draws is the game's to say, through an overlay inside it, and the shell
// cannot see it.
ColumnLayout {
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
            glyph: "memory",
            name: Translation.tr("CPU"),
            value: ResourceUsage.cpuReady ? root.percent(ResourceUsage.cpuUsage) : "--",
            detail: ResourceUsage.maxAvailableCpuString.length > 0 && ResourceUsage.maxAvailableCpuString !== "--"
                ? Translation.tr("Up to %1").arg(ResourceUsage.maxAvailableCpuString) : "",
            history: ResourceUsage.cpuUsageHistory
        }];
        if (ResourceUsage.gpuKind === "busy")
            list.push({
                key: "gpu",
                glyph: "developer_board",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? root.percent(ResourceUsage.gpuUsage) : "--",
                detail: "",
                history: ResourceUsage.gpuUsageHistory
            });
        else if (ResourceUsage.gpuKind === "clock")
            list.push({
                key: "gpu",
                glyph: "developer_board",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? `${Math.round(ResourceUsage.gpuClock)} MHz` : "--",
                detail: Translation.tr("Clock, of %1 MHz").arg(Math.round(ResourceUsage.gpuMaxClock)),
                history: ResourceUsage.gpuUsageHistory
            });
        list.push({
            key: "ram",
            glyph: "memory_alt",
            name: Translation.tr("RAM"),
            value: ResourceUsage.ready ? root.percent(ResourceUsage.memoryUsedPercentage) : "--",
            detail: ResourceUsage.ready
                ? Translation.tr("%1 of %2").arg(ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)).arg(ResourceUsage.maxAvailableMemoryString) : "",
            history: ResourceUsage.memoryUsageHistory
        });
        return list;
    }
    readonly property var shown: root.readings.find(reading => reading.key === Persistent.states.gameBar.performanceShown) ?? root.readings[0]

    Layout.fillWidth: true
    spacing: ExLooks.spacing.s

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        Repeater {
            model: root.readings

            // A tile with the reading as its state, picked as a tile is
            // switched on.
            ExToggleTile {
                id: tile

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitWidth: 0
                checkable: false
                checked: tile.modelData.key === root.shown.key
                glyph: tile.modelData.glyph
                text: tile.modelData.name
                subtitle: tile.modelData.value
                onClicked: Persistent.states.gameBar.performanceShown = tile.modelData.key
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: graphColumn.implicitHeight + 2 * ExLooks.spacing.m
        radius: ExLooks.radius.tile
        color: ExLooks.colors.surfaceSunken

        ColumnLayout {
            id: graphColumn

            x: ExLooks.spacing.m
            y: ExLooks.spacing.m
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.s

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
                    elide: Text.ElideRight
                }
            }

            // The graph between its scale: the top and the bottom on the
            // right, how long it reaches back under it.
            Item {
                Layout.fillWidth: true
                implicitHeight: 96 + ExLooks.spacing.xs + scaleLength.implicitHeight

                ExGameBarGraph {
                    id: graph

                    width: parent.width - scaleTop.implicitWidth - ExLooks.spacing.s
                    height: 96
                    values: root.shown.history
                    points: ResourceUsage.historyLength
                }
                // A hairline along the bottom of the graph, its floor.
                Rectangle {
                    y: graph.height - 1
                    width: graph.width
                    height: 1
                    color: ExLooks.colors.border
                }
                ExText {
                    id: scaleTop

                    anchors.right: parent.right
                    y: -2
                    text: "100"
                    role: "caption"
                    dim: true
                    font.features: ({ "tnum": 1 })
                }
                ExText {
                    anchors.right: parent.right
                    y: graph.height - implicitHeight + 2
                    text: "0"
                    role: "caption"
                    dim: true
                }
                ExText {
                    id: scaleLength

                    anchors.bottom: parent.bottom
                    // The card is read every second, the rest at the
                    // interval the settings give.
                    text: Translation.tr("%1 seconds").arg(Math.round(ResourceUsage.historyLength * (root.shown.key === "gpu" ? 1000 : (Config.options?.resources?.updateInterval ?? 3000)) / 1000))
                    role: "caption"
                    dim: true
                }
            }
        }
    }
}
