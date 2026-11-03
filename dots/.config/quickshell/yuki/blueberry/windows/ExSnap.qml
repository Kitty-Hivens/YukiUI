pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs.core
import qs.blueberry.looks

// Snap, as Windows does it: a window dragged to a side of the screen takes that
// half, to a corner that quarter, to the top the whole of it. Where it would go
// is shown while it is held there. A maximised or snapped window pulled away
// takes back the size it had, under the pointer, as it starts to move.
//
// The drag itself is heard through the drag-report plugin: Hyprland says
// nothing on its socket while a window is moved.
Scope {
    id: root

    required property var placement

    readonly property bool enabled: Config.options.blueberry.snap.enabled

    /** The window being moved, or empty. */
    property string dragged: ""
    /**
     * Where it stood before the drag, { at, size }, or null: what a snap goes
     * back to. Read where it stands when it is let go of, a window snapped by
     * dragging went back to the edge it was dragged to, half off the screen.
     */
    property var draggedFrom: null
    /**
     * The size a placed window was pulled away to, or null. The pull gives it
     * back under the pointer through the plugin, which has to arrive while
     * the drag is still on: a window flicked away and let go of at once kept
     * the size of its half, no longer placed. So it is given that size again
     * as the drag ends, which changes nothing when the pull came in time.
     */
    property var pulledTo: null
    /** Where it would go if let go of now, one of the placement zones, or empty. */
    property string zone: ""
    /** The screen that zone is on, and the zone's rectangle on it in its own coordinates. */
    property string zoneScreen: ""
    property var zoneRect: null

    /** The monitors, read as a drag begins: { name, x, y, w, h, area }. */
    property var monitors: []

    // How close to an edge counts as touching it, and how far from a corner
    // along an edge counts as the corner.
    readonly property int edge: 4
    function cornerReach(length: real): real {
        return Math.min(220, length / 5);
    }

    function zoneAt(x: real, y: real) {
        const monitor = root.monitors.find(m => x >= m.x && x < m.x + m.w && y >= m.y && y < m.y + m.h);
        if (!monitor || !root.enabled) {
            root.zone = "";
            return;
        }
        const left = x <= monitor.x + root.edge;
        const right = x >= monitor.x + monitor.w - 1 - root.edge;
        const top = y <= monitor.y + root.edge;
        const bottom = y >= monitor.y + monitor.h - 1 - root.edge;
        const nearTop = y <= monitor.y + root.cornerReach(monitor.h);
        const nearBottom = y >= monitor.y + monitor.h - root.cornerReach(monitor.h);
        const nearLeft = x <= monitor.x + root.cornerReach(monitor.w);
        const nearRight = x >= monitor.x + monitor.w - root.cornerReach(monitor.w);
        let zone = "";
        if (left)
            zone = nearTop ? "topleft" : nearBottom ? "bottomleft" : "left";
        else if (right)
            zone = nearTop ? "topright" : nearBottom ? "bottomright" : "right";
        else if (top)
            zone = nearLeft ? "topleft" : nearRight ? "topright" : "maximized";
        else if (bottom && (nearLeft || nearRight))
            zone = nearLeft ? "bottomleft" : "bottomright";
        root.zone = zone;
        if (zone.length === 0)
            return;
        const rect = root.placement.zoneRect(monitor.area, zone);
        root.zoneScreen = monitor.name;
        root.zoneRect = { x: rect.x - monitor.x, y: rect.y - monitor.y, w: rect.w, h: rect.h };
    }

    Process {
        id: monitorReader
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).map(monitor => {
                        const scale = monitor.scale || 1;
                        const turned = monitor.transform % 2 === 1;
                        return {
                            name: monitor.name,
                            x: monitor.x,
                            y: monitor.y,
                            w: (turned ? monitor.height : monitor.width) / scale,
                            h: (turned ? monitor.width : monitor.height) / scale,
                            area: root.placement.placementArea(monitor)
                        };
                    });
                } catch (error) {
                    root.monitors = [];
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "windowdrag")
                return;
            const parts = event.data.split(",");
            if (parts[0] === "begin") {
                const [, address, mode, x, y, w, h] = parts;
                if (mode !== "move") {
                    // Resized by hand, it is no longer where it was put.
                    root.placement.release(address);
                    return;
                }
                root.dragged = address;
                root.zone = "";
                monitorReader.running = true;
                // A placed window goes back to where it stood before it was
                // placed. The plugin says where any other stood, from 1.1 on.
                root.draggedFrom = root.placement.placed[address]?.before
                    ?? (h !== undefined ? { at: [Number(x), Number(y)], size: [Number(w), Number(h)] } : null);
                // Pulled away, a placed window takes back its own size under
                // the pointer and goes on being dragged from there.
                const size = root.placement.sizeBefore(address);
                root.pulledTo = size;
                if (size) {
                    Quickshell.execDetached(["hyprctl", "eval", `if hl.plugin.drag_report and hl.plugin.drag_report.regrab then hl.plugin.drag_report.regrab(${size[0]}, ${size[1]}) end`]);
                    root.placement.release(address);
                }
            } else if (parts[0] === "move" && root.dragged.length > 0) {
                root.zoneAt(Number(parts[1]), Number(parts[2]));
            } else if (parts[0] === "end") {
                const [, address, mode, x, y] = parts;
                if (mode === "move" && address === root.dragged) {
                    root.zoneAt(Number(x), Number(y));
                    if (root.zone.length > 0)
                        root.placement.place(address, root.zone, root.draggedFrom);
                    else if (root.pulledTo && root.placement.usable(address))
                        Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.window.resize({ window = "address:${address}", x = ${root.pulledTo[0]}, y = ${root.pulledTo[1]} }))`]);
                }
                root.pulledTo = null;
                root.dragged = "";
                root.draggedFrom = null;
                root.zone = "";
            }
        }
    }

    // Where the window would go, on the screen it would go on.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: preview

            required property var modelData
            readonly property bool showing: root.zone.length > 0 && root.zoneScreen === preview.modelData.name

            screen: modelData
            visible: preview.showing || plate.opacity > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:snapPreview"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // Takes no pointer: the drag goes on under it.
            mask: Region {}

            Rectangle {
                id: plate

                readonly property real inset: ExLooks.spacing.s
                x: (root.zoneRect?.x ?? 0) + plate.inset
                y: (root.zoneRect?.y ?? 0) + plate.inset
                width: Math.max(0, (root.zoneRect?.w ?? 0) - 2 * plate.inset)
                height: Math.max(0, (root.zoneRect?.h ?? 0) - 2 * plate.inset)
                radius: ExLooks.radius.panel
                color: Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.22)
                border.width: 2
                border.color: Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.7)
                opacity: preview.showing ? 1 : 0
                scale: preview.showing ? 1 : 0.97

                Behavior on x {
                    enabled: plate.opacity > 0
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on y {
                    enabled: plate.opacity > 0
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on width {
                    enabled: plate.opacity > 0
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on height {
                    enabled: plate.opacity > 0
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }
                Behavior on scale {
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
            }
        }
    }
}
