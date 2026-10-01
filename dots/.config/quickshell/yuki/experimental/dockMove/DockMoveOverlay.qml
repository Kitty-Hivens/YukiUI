pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core
import qs.experimental.looks

// What one screen shows while the dock changes edges: where it would land
// while it is being dragged, and then the dock itself travelling there.
//
// The dock cannot animate across the screen on its own: it is a layer window
// that the compositor places against one edge or another and nowhere between.
// So for the length of the move it is drawn here instead, its plate and its
// icons, each going from where it stood to where it now stands, and the real
// dock shows up again underneath once they have arrived.
Scope {
    id: root

    required property var screenModel
    /** The dock's side of the move: phase, target, shapes, and the ready call. */
    required property var mover
    /** How long an island is, what it holds end to end, for where a drag would put one. */
    property real islandLength: 0

    readonly property string screenName: root.screenModel?.name ?? ""
    readonly property var before: root.mover.shapesBefore[root.screenName] ?? null
    readonly property var after: root.mover.shapesAfter[root.screenName] ?? null

    function mix(a: real, b: real, t: real): real {
        return a + (b - a) * t;
    }

    function mixRect(a, b, t: real): var {
        return { x: root.mix(a.x, b.x, t), y: root.mix(a.y, b.y, t), w: root.mix(a.w, b.w, t), h: root.mix(a.h, b.h, t) };
    }

    function ease(t: real): real {
        const clamped = Math.max(0, Math.min(1, t));
        return clamped < 0.5 ? 4 * clamped * clamped * clamped : 1 - Math.pow(-2 * clamped + 2, 3) / 2;
    }

    /** The screen edge nearest a point on this screen. */
    function nearestEdge(x: real, y: real, width: real, height: real): string {
        const distance = { left: x, right: width - x, top: y, bottom: height - y };
        return Object.keys(distance).reduce((best, edge) => distance[edge] < distance[best] ? edge : best);
    }

    // Where the dock would stand on an edge, for the drag: the same place and
    // shape it will take there, in whichever of the three ways it stands.
    function landing(edge: string, width: real, height: real): var {
        const style = Config.options.experimental.dock.style;
        const thickness = ExLooks.dock.thickness;
        const gap = style === "attached" ? 0 : ExLooks.dock.floatingGap;
        const vertical = edge === "left" || edge === "right";
        const span = vertical ? height : width;
        const length = style === "island" ? Math.min(root.islandLength, span - 2 * gap) : span - 2 * gap;
        const along = style === "island" && Config.options.experimental.dock.alignment === "start" ? gap : (span - length) / 2;
        const radius = style === "attached" ? 0 : ExLooks.dock.floatingRadius;
        if (edge === "top")
            return { x: along, y: gap, w: length, h: thickness, radius: radius };
        if (edge === "left")
            return { x: gap, y: along, w: thickness, h: length, radius: radius };
        if (edge === "right")
            return { x: width - thickness - gap, y: along, w: thickness, h: length, radius: radius };
        return { x: along, y: height - thickness - gap, w: length, h: thickness, radius: radius };
    }

    Loader {
        active: root.mover.phase !== "" || root.mover.moveTarget !== ""

        sourceComponent: PanelWindow {
            id: overlay

            /** Milliseconds into the flight. */
            property real clock: 0
            readonly property int stagger: 18
            readonly property int travel: 460
            readonly property var pieces: {
                const from = root.before?.items ?? [];
                const to = root.after?.items ?? [];
                const keys = [];
                for (const item of [...from, ...to])
                    if (!keys.includes(item.key))
                        keys.push(item.key);
                return keys.map((key, index) => ({
                    key: key,
                    index: index,
                    from: from.find(item => item.key === key) ?? null,
                    to: to.find(item => item.key === key) ?? null
                }));
            }
            readonly property int total: overlay.travel + overlay.stagger * Math.max(0, overlay.pieces.length - 1)
            // Faded out while the dock fades in under it, so the two cross rather
            // than the dock popping up with what this does not draw, the button
            // of the application in front and the marks of the running ones.
            property real shown: root.mover.phase === "reveal" ? 0 : 1

            Behavior on shown {
                NumberAnimation {
                    duration: ExLooks.motion.normal
                    easing.type: Easing.OutCubic
                }
            }

            /** How far one piece is along its way at the current moment. */
            function progressOf(index: int): real {
                return root.ease((overlay.clock - overlay.stagger * index) / overlay.travel);
            }

            function rectOf(piece): var {
                const from = piece.from ?? piece.to;
                const to = piece.to ?? piece.from;
                return root.mixRect(from, to, overlay.progressOf(piece.index));
            }

            // What the icons take up right now, with the dock's padding round
            // them. The plate closes in on this as it leaves, travels as this,
            // and opens out from it as it arrives, rather than stretching as
            // one long shape across the screen.
            readonly property var cluster: {
                const padding = ExLooks.spacing.s;
                const rects = overlay.pieces.map(piece => overlay.rectOf(piece));
                if (rects.length === 0)
                    return null;
                const left = Math.min(...rects.map(rect => rect.x)) - padding;
                const top = Math.min(...rects.map(rect => rect.y)) - padding;
                const right = Math.max(...rects.map(rect => rect.x + rect.w)) + padding;
                const bottom = Math.max(...rects.map(rect => rect.y + rect.h)) + padding;
                return { x: left, y: top, w: right - left, h: bottom - top };
            }

            screen: root.screenModel
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:dockMove"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // Seen, never clicked, except while the dock is dragged: then it
            // takes the drag, all of it, to tell where the dock is going.
            readonly property bool taking: root.mover.moveTarget !== "" && root.mover.phase === ""
            mask: Region {
                item: overlay.taking ? catcher : null
            }

            DropArea {
                id: catcher

                anchors.fill: parent
                enabled: overlay.taking
                keys: ["application/x-yuki-dock"]
                // The first positions a drag reports on entering are the
                // middle of the screen, not where the pointer is, and the
                // middle is as near to one edge as another: the frame set off
                // for the top before turning for the edge the pointer was at.
                // They are passed over until the pointer has really moved.
                property point enteredAt: Qt.point(-1, -1)

                onEntered: drag => catcher.enteredAt = Qt.point(drag.x, drag.y)
                onPositionChanged: drag => {
                    if (drag.x === catcher.enteredAt.x && drag.y === catcher.enteredAt.y)
                        return;
                    catcher.enteredAt = Qt.point(-1, -1);
                    root.mover.moveTarget = root.nearestEdge(drag.x, drag.y, overlay.width, overlay.height);
                }
                onDropped: drop => {
                    drop.acceptProposedAction();
                    const target = root.nearestEdge(drop.x, drop.y, overlay.width, overlay.height);
                    root.mover.moveTarget = "";
                    root.mover.moveTo(target);
                }
            }

            // Ready once it has had a frame to be drawn in, so the dock is not
            // hidden before this stands in for it.
            Timer {
                running: root.mover.phase === "prepare"
                interval: 50
                onTriggered: root.mover.overlayReady(root.screenName)
            }

            NumberAnimation {
                running: root.mover.phase === "fly"
                target: overlay
                property: "clock"
                from: 0
                to: overlay.total
                duration: overlay.total
                onFinished: root.mover.flightDone(root.screenName)
            }

            // The drag: where the dock will go when let go of.
            Rectangle {
                readonly property var place: root.landing(root.mover.moveTarget, overlay.width, overlay.height)

                visible: root.mover.moveTarget !== "" && root.mover.phase === ""
                x: place.x
                y: place.y
                width: place.w
                height: place.h
                radius: place.radius
                color: Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.16)
                border.width: 2
                border.color: ExLooks.colors.accent

                Behavior on x {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on y {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on width {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on height {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
            }

            // The plate: from the old shape in to the icons, along with them,
            // and out to the new shape.
            ExSurface {
                id: plate

                readonly property var from: root.before?.plate ?? null
                readonly property var to: root.after?.plate ?? root.before?.plate ?? null
                readonly property real t: overlay.clock / overlay.total
                readonly property real closing: root.ease(plate.t / 0.3)
                readonly property real opening: root.ease((plate.t - 0.7) / 0.3)
                readonly property var middle: overlay.cluster ?? plate.from
                readonly property var rect: !plate.from ? null
                    : plate.opening > 0 ? root.mixRect(plate.middle, plate.to, plate.opening)
                    : root.mixRect(plate.from, plate.middle, plate.closing)
                // Round while it travels, whatever it is at either end.
                readonly property real travelRadius: ExLooks.dock.floatingRadius

                visible: plate.from !== null && root.mover.phase !== ""
                x: plate.rect?.x ?? 0
                y: plate.rect?.y ?? 0
                width: plate.rect?.w ?? 0
                height: plate.rect?.h ?? 0
                radius: !plate.from ? 0
                    : plate.opening > 0 ? root.mix(plate.travelRadius, plate.to.radius, plate.opening)
                    : root.mix(plate.from.radius, plate.travelRadius, plate.closing)
                // Arriving as the dock it stands in for: an attached one has
                // neither a shadow nor a hairline all round.
                elevation: plate.opening > 0 ? root.mix(1, plate.to.elevation ?? 1, plate.opening) : root.mix(plate.from?.elevation ?? 1, 1, plate.closing)
                bordered: plate.opening >= 1 ? (plate.to.bordered ?? true) : plate.closing <= 0 ? (plate.from?.bordered ?? true) : true
                opacity: overlay.shown
                color: ExLooks.colors.dockPlate
            }

            // The tray and the status block, as pictures: fading where they
            // stood as the plate closes away from them, and showing up where
            // they now stand as it opens out over them.
            Repeater {
                model: root.mover.phase !== "" ? (root.before?.pictures ?? []) : []

                Image {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    source: modelData.url
                    opacity: (1 - plate.closing) * overlay.shown
                    visible: opacity > 0
                }
            }
            Repeater {
                model: root.mover.phase === "fly" || root.mover.phase === "reveal" ? (root.after?.pictures ?? []) : []

                Image {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    source: modelData.url
                    opacity: plate.opening * overlay.shown
                    visible: opacity > 0
                }
            }

            // The icons, each a moment after the one before it.
            Repeater {
                model: root.mover.phase !== "" ? overlay.pieces : []

                Item {
                    id: piece

                    required property var modelData
                    readonly property var from: piece.modelData.from ?? piece.modelData.to
                    readonly property var to: piece.modelData.to ?? piece.modelData.from
                    readonly property real t: overlay.progressOf(piece.modelData.index)
                    readonly property var looks: piece.modelData.to ?? piece.modelData.from

                    x: root.mix(piece.from.x, piece.to.x, piece.t)
                    y: root.mix(piece.from.y, piece.to.y, piece.t)
                    width: root.mix(piece.from.w, piece.to.w, piece.t)
                    height: root.mix(piece.from.h, piece.to.h, piece.t)
                    // Something only on one side of the move fades out or in on the spot.
                    opacity: (piece.modelData.from === null ? piece.t : (piece.modelData.to === null ? 1 - piece.t : 1)) * overlay.shown

                    ExGlyph {
                        anchors.centerIn: parent
                        visible: piece.looks.kind === "launcher"
                        text: "apps"
                        size: ExLooks.dock.launcherGlyph
                        color: ExLooks.colors.accent
                    }
                    IconImage {
                        anchors.centerIn: parent
                        visible: piece.looks.kind === "app"
                        implicitSize: ExLooks.dock.icon
                        source: piece.looks.icon ?? ""
                    }
                }
            }
        }
    }
}
