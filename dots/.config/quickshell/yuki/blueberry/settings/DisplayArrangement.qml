pragma ComponentBehavior: Bound

import QtQuick

import qs.core.services
import qs.blueberry.looks
import "../../core/functions/arrange.js" as Arrange

// The displays as Windows draws them above its display settings: numbered
// rectangles in their places, the chosen one in the accent colour, dragged to
// rearrange. The geometry is arrange.js's, this only draws it and reports back.
// Displays that are off wait along the bottom, where they can be chosen but not
// placed: switching one on is what places it.
Item {
    id: root

    property var plan: []
    property string selectedName: ""

    signal picked(string name)
    signal moved(string name, int x, int y)

    readonly property var activePlan: root.plan.filter(entry => entry.enabled)
    readonly property var offPlan: root.plan.filter(entry => !entry.enabled)
    readonly property real padding: 32
    readonly property real trayHeight: root.offPlan.length > 0 ? 48 : 0
    property var guides: []

    readonly property rect bounds: {
        const box = Arrange.boundsOf(root.plan);
        return Qt.rect(box.x, box.y, box.width, box.height);
    }
    readonly property real viewScale: Math.max(0.01, Math.min(0.16,
        (root.width - 2 * root.padding) / root.bounds.width,
        (root.height - root.trayHeight - 2 * root.padding) / root.bounds.height))
    readonly property real originX: (root.width - root.bounds.width * root.viewScale) / 2 - root.bounds.x * root.viewScale
    readonly property real originY: (root.height - root.trayHeight - root.bounds.height * root.viewScale) / 2 - root.bounds.y * root.viewScale

    // Keyed by name, so an edit moves the tiles rather than building new ones
    // already in their new places.
    readonly property string tileKey: root.activePlan.map(entry => entry.name).join(",")
    property var tileNames: []
    onTileKeyChanged: root.tileNames = root.activePlan.map(entry => entry.name)
    Component.onCompleted: root.tileNames = root.activePlan.map(entry => entry.name)

    function numberOf(name: string): int {
        return root.plan.findIndex(entry => entry.name === name) + 1;
    }

    Rectangle {
        anchors.fill: parent
        radius: ExLooks.radius.card
        color: ExLooks.colors.surfaceSunken
        border.width: 1
        border.color: ExLooks.colors.hairline
    }

    Repeater {
        model: root.activePlan.length > 1 ? root.guides : []

        Rectangle {
            required property var modelData
            color: ExLooks.colors.accent
            opacity: 0.6
            x: modelData.axis === "x" ? root.originX + modelData.position * root.viewScale : 0
            y: modelData.axis === "y" ? root.originY + modelData.position * root.viewScale : 0
            width: modelData.axis === "x" ? 1 : root.width
            height: modelData.axis === "y" ? 1 : root.height - root.trayHeight
        }
    }

    Repeater {
        model: root.tileNames

        Item {
            id: tile

            required property string modelData
            readonly property var entry: root.plan.find(item => item.name === tile.modelData) ?? null
            readonly property var logical: tile.entry ? Arrange.logicalSize(tile.entry) : ({ width: 1, height: 1 })
            readonly property bool selected: root.selectedName === tile.modelData
            property real liveX: 0
            property real liveY: 0
            property bool dragging: false
            property bool blocked: false
            property bool settled: false

            function sync() {
                if (tile.dragging || !tile.entry)
                    return;
                tile.liveX = tile.entry.x;
                tile.liveY = tile.entry.y;
            }

            visible: tile.entry !== null
            x: root.originX + tile.liveX * root.viewScale
            y: root.originY + tile.liveY * root.viewScale
            width: tile.logical.width * root.viewScale
            height: tile.logical.height * root.viewScale
            z: tile.dragging ? 2 : 1

            onEntryChanged: tile.sync()
            Component.onCompleted: {
                tile.sync();
                Qt.callLater(() => tile.settled = true);
            }

            // On where the display is, not where it is drawn, so resizing the
            // window rescales the picture without sending anything travelling.
            Behavior on liveX {
                enabled: tile.settled && !tile.dragging
                NumberAnimation {
                    duration: ExLooks.motion.normal
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on liveY {
                enabled: tile.settled && !tile.dragging
                NumberAnimation {
                    duration: ExLooks.motion.normal
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 6
                color: tile.blocked ? ExLooks.colors.destructive
                    : tile.selected ? ExLooks.colors.accent
                    : mouse.containsMouse ? ExLooks.colors.tonalDeep : ExLooks.colors.control
                border.width: 1
                border.color: ExLooks.colors.hairline

                Behavior on color {
                    ColorAnimation {
                        duration: ExLooks.motion.fast
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    ExText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(root.numberOf(tile.modelData))
                        font.pixelSize: Math.max(16, Math.min(40, tile.height * 0.34))
                        font.weight: ExLooks.font.weightTitle
                        color: tile.selected || tile.blocked ? ExLooks.colors.accentInk : ExLooks.colors.text
                    }
                    ExText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: tile.height > 56
                        text: tile.modelData
                        role: "caption"
                        color: tile.selected || tile.blocked ? ExLooks.colors.accentInk : ExLooks.colors.textDim
                    }
                }
            }

            MouseArea {
                id: mouse

                property real grabX: 0
                property real grabY: 0

                anchors.fill: parent
                hoverEnabled: true
                // The page scrolls, and a display being dragged is not a scroll.
                preventStealing: true
                cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                onPressed: event => {
                    root.picked(tile.modelData);
                    mouse.grabX = event.x;
                    mouse.grabY = event.y;
                    tile.dragging = true;
                }
                onPositionChanged: event => {
                    if (!tile.dragging || root.activePlan.length < 2)
                        return;
                    const proposedX = tile.liveX + (event.x - mouse.grabX) / root.viewScale;
                    const proposedY = tile.liveY + (event.y - mouse.grabY) / root.viewScale;
                    const snapped = Arrange.snap(root.plan, tile.modelData, proposedX, proposedY, 40 / root.viewScale);
                    tile.liveX = snapped.x;
                    tile.liveY = snapped.y;
                    root.guides = snapped.guides;
                    const probe = root.plan.map(entry => entry.name === tile.modelData ? Object.assign({}, entry, { x: snapped.x, y: snapped.y }) : entry);
                    tile.blocked = Arrange.findOverlap(probe) !== null;
                }
                onReleased: {
                    if (!tile.dragging)
                        return;
                    tile.dragging = false;
                    tile.blocked = false;
                    root.guides = [];
                    if (!tile.entry || (tile.liveX === tile.entry.x && tile.liveY === tile.entry.y))
                        return;
                    // Pushed clear of whatever it was dropped on, and put back
                    // when that ends where it started.
                    const settled = Arrange.resolveOverlap(root.plan, tile.modelData, tile.liveX, tile.liveY);
                    const candidate = root.plan.map(entry => entry.name === tile.modelData ? Object.assign({}, entry, { x: settled.x, y: settled.y }) : entry);
                    const key = plan => JSON.stringify(Arrange.normalize(plan).filter(entry => entry.enabled).map(entry => [entry.name, entry.x, entry.y]).sort());
                    if (key(candidate) === key(root.plan)) {
                        tile.sync();
                        return;
                    }
                    root.moved(tile.modelData, settled.x, settled.y);
                }
                onCanceled: {
                    tile.dragging = false;
                    tile.blocked = false;
                    root.guides = [];
                    tile.sync();
                }
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: ExLooks.spacing.m
        spacing: ExLooks.spacing.s
        visible: root.offPlan.length > 0

        Repeater {
            model: root.offPlan

            ParkedTile {}
        }
    }

    component ParkedTile: Rectangle {
        id: parked

        required property var modelData
        readonly property bool selected: root.selectedName === parked.modelData.name

        implicitWidth: parkedLabel.implicitWidth + 2 * ExLooks.spacing.m
        implicitHeight: 32
        radius: 6
        color: parked.selected ? ExLooks.colors.tonal : "transparent"
        border.width: 1
        border.color: parked.selected ? ExLooks.colors.accent : ExLooks.colors.border

        ExText {
            id: parkedLabel
            anchors.centerIn: parent
            text: Translation.tr("%1  ·  %2  ·  off").arg(root.numberOf(parked.modelData.name)).arg(parked.modelData.name)
            role: "caption"
            color: parked.selected ? ExLooks.colors.tonalInk : ExLooks.colors.textDim
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked(parked.modelData.name)
        }
    }
}
