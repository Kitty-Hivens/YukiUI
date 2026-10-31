pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks

// How hard the machine is working: a tile for each reading, its own last
// while drawn faintly behind it, and the one picked drawn large under them on
// a card, as quick settings sets off what is playing. A reading running high
// turns from the accent to amber and then to red, on the tiles and the graph.
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

    /** The colour a load is drawn in: the accent, amber past 60%, red past 85%. */
    function loadColor(load: real): color {
        if (load > 0.85)
            return ExLooks.colors.destructive;
        if (load > 0.6)
            return ExLooks.colors.warning;
        return ExLooks.colors.accent;
    }

    // The card is read every second, the rest at the interval the settings give.
    readonly property real slowInterval: Config.options?.resources?.updateInterval ?? 3000

    readonly property var readings: {
        const list = [{
            key: "cpu",
            name: Translation.tr("CPU"),
            value: ResourceUsage.cpuReady ? root.percent(ResourceUsage.cpuUsage) : "--",
            load: ResourceUsage.cpuUsage,
            detail: ResourceUsage.maxAvailableCpuString.length > 0 && ResourceUsage.maxAvailableCpuString !== "--"
                ? Translation.tr("Up to %1").arg(ResourceUsage.maxAvailableCpuString) : "",
            history: ResourceUsage.cpuUsageHistory,
            interval: root.slowInterval
        }];
        if (ResourceUsage.gpuKind === "busy")
            list.push({
                key: "gpu",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? root.percent(ResourceUsage.gpuUsage) : "--",
                load: ResourceUsage.gpuUsage,
                detail: "",
                history: ResourceUsage.gpuUsageHistory,
                interval: 1000
            });
        else if (ResourceUsage.gpuKind === "clock")
            list.push({
                key: "gpu",
                name: Translation.tr("GPU"),
                value: ResourceUsage.gpuUsageHistory.length > 0 ? `${Math.round(ResourceUsage.gpuClock)} MHz` : "--",
                load: ResourceUsage.gpuUsage,
                detail: Translation.tr("Clock, of %1 MHz").arg(Math.round(ResourceUsage.gpuMaxClock)),
                history: ResourceUsage.gpuUsageHistory,
                interval: 1000
            });
        list.push({
            key: "ram",
            name: Translation.tr("RAM"),
            value: ResourceUsage.ready ? root.percent(ResourceUsage.memoryUsedPercentage) : "--",
            load: ResourceUsage.memoryUsedPercentage,
            detail: ResourceUsage.ready
                ? Translation.tr("%1 of %2").arg(ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)).arg(ResourceUsage.maxAvailableMemoryString) : "",
            history: ResourceUsage.memoryUsageHistory,
            interval: root.slowInterval
        });
        return list;
    }
    readonly property var shown: root.readings.find(reading => reading.key === Persistent.states.gameBar.performanceShown) ?? root.readings[0]
    readonly property color shownInk: root.loadColor(root.shown.load)

    Layout.fillWidth: true
    spacing: ExLooks.spacing.s

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.s

        Repeater {
            model: root.readings

            // A reading: its name, its value, and its last while faintly
            // behind them. Picked, it is filled as a switched on tile is.
            AbstractButton {
                id: tile

                required property var modelData
                readonly property bool picked: tile.modelData.key === root.shown.key
                readonly property color ink: tile.picked ? ExLooks.colors.accentInk : ExLooks.colors.controlInk

                ExPrimaryOnly {
                    z: 1
                }

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitWidth: 0
                implicitHeight: 72
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                onClicked: Persistent.states.gameBar.performanceShown = tile.modelData.key

                background: Rectangle {
                    radius: ExLooks.radius.tile
                    color: tile.picked ? ExLooks.colors.accent : ExLooks.colors.control

                    Behavior on color {
                        ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                    }

                    // Kept off the rounded corners, which it would poke out of.
                    ExGameBarGraph {
                        anchors.fill: parent
                        anchors.topMargin: 30
                        anchors.leftMargin: ExLooks.spacing.s
                        anchors.rightMargin: ExLooks.spacing.s
                        anchors.bottomMargin: ExLooks.spacing.s
                        opacity: tile.picked ? 0.45 : 0.7
                        values: tile.modelData.history
                        points: Math.max(2, tile.modelData.history.length)
                        ink: tile.picked ? ExLooks.colors.accentInk : root.loadColor(tile.modelData.load)
                        strokeWidth: 1.5
                    }

                    ExStateLayer {
                        ink: tile.ink
                        hovered: tile.hovered
                        pressed: tile.down
                    }
                }
                contentItem: Item {
                    ColumnLayout {
                        x: ExLooks.spacing.m
                        y: ExLooks.spacing.s + 2
                        width: parent.width - 2 * ExLooks.spacing.m
                        spacing: 0

                        ExText {
                            Layout.fillWidth: true
                            text: tile.modelData.name
                            role: "caption"
                            color: tile.ink
                            opacity: 0.8
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: tile.modelData.value
                            role: "label"
                            font.weight: ExLooks.font.weightTitle
                            font.features: ({ "tnum": 1 })
                            color: tile.ink
                            elide: Text.ElideRight
                        }
                    }
                }
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
            spacing: ExLooks.spacing.xs

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.s

                // Large and light, as the lock screen sets its clock.
                ExText {
                    text: root.shown.value
                    font.pixelSize: 40
                    font.weight: 300
                    font.features: ({ "tnum": 1 })
                    color: root.shownInk

                    Behavior on color {
                        ColorAnimation { duration: ExLooks.motion.normal }
                    }
                }
                ExText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 8
                    text: root.shown.detail
                    role: "caption"
                    dim: true
                    elide: Text.ElideRight
                }
            }

            // The graph between its scale: the top and the bottom on the
            // right, how far it reaches back under it. A history still
            // filling is spread over the whole width, and says how far back
            // it really goes.
            Item {
                Layout.fillWidth: true
                implicitHeight: 96 + ExLooks.spacing.xs + scaleLength.implicitHeight

                ExGameBarGraph {
                    id: graph

                    width: parent.width - scaleTop.implicitWidth - ExLooks.spacing.s
                    height: 96
                    values: root.shown.history
                    points: Math.max(2, root.shown.history.length)
                    ink: root.shownInk
                }
                // The floor of the graph.
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
                    visible: root.shown.history.length > 1
                    text: Translation.tr("%1 seconds").arg(Math.round((root.shown.history.length - 1) * root.shown.interval / 1000))
                    role: "caption"
                    dim: true
                }
            }
        }
    }
}
