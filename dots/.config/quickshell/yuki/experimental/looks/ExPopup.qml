import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.core.services

/**
 * A flyout that comes out of the dock, as a window of its own.
 *
 * A popup of the dock's window rather than a layer covering the screen: it can
 * reach past the dock, the compositor keeps it on screen, and nothing sits over
 * the desktop while it is shut. It takes no grab of its own, since a grabbed
 * popup is shut by the compositor on the first click outside and vanishes
 * without its way out. A focus grab over it and the dock reports that click
 * instead, and the popup closes the way it opened.
 *
 * It rests a spacing away from the dock, opposite the button that opened it.
 */
PopupWindow {
    id: root

    property bool open: false
    property string edge: "bottom"
    /** The dock's window, and the plane the dock is drawn on inside it. */
    required property var dockWindow
    required property Item dockSurface
    /** The button the popup belongs to. The popup is centred on it along the dock. */
    property Item opener: null
    property real padding: ExLooks.spacing.l
    property real surfaceRadius: ExLooks.radius.panel
    /** How it moves: "menu" or "panel", as ExFlyoutSurface takes it. */
    property string motion: "menu"

    default property alias content: holder.data

    signal dismissRequested

    readonly property real gap: ExLooks.spacing.s
    // Room around the plane for its shadow, and for the way in on the dock side.
    readonly property real shadowRoom: 32

    function toggle(item: Item) {
        if (root.open && root.opener === item) {
            root.open = false;
            return;
        }
        root.opener = item;
        root.anchor.updateAnchor();
        root.open = true;
    }

    color: "transparent"
    visible: root.open || surface.progress > 0
    implicitWidth: holder.width + 2 * root.padding + 2 * root.shadowRoom
    implicitHeight: holder.height + 2 * root.padding + 2 * root.shadowRoom

    anchor {
        window: root.dockWindow
        // Kept on screen here rather than by the compositor. Sliding the window
        // back counts the shadow room around the plane as part of it, so a
        // popup near a corner stopped short of it by that much.
        adjustment: PopupAdjustment.None
        edges: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom : root.edge === "left" ? Edges.Right : Edges.Left
        gravity: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom : root.edge === "left" ? Edges.Right : Edges.Left
        // A point, not a box: along the dock it is the middle of the button,
        // across it the dock's inner edge, moved out by the gap and back in by
        // the shadow room the popup carries around its plane.
        //
        // Along the dock the plane does not reach past the dock's ends. One
        // opened from the far end, like quick settings, sits in the corner,
        // as far from the screen edge as it is from the dock. A dock that
        // stands off the edge already keeps that distance, so there the plane
        // lines up with the dock's end.
        onAnchoring: {
            if (!root.opener)
                return;
            const button = root.opener.mapToItem(null, root.opener.width / 2, root.opener.height / 2);
            const dock = root.dockSurface.mapToItem(null, 0, 0);
            const inset = root.shadowRoom - root.gap;
            const margin = root.dockWindow.detached ? 0 : root.gap;
            const vertical = root.edge === "left" || root.edge === "right";
            const half = (vertical ? surface.height : surface.width) / 2;
            const start = (vertical ? dock.y : dock.x) + margin + half;
            const end = (vertical ? dock.y + root.dockSurface.height : dock.x + root.dockSurface.width) - margin - half;
            const along = Math.max(start, Math.min(end, vertical ? button.y : button.x));
            let x = vertical ? button.x : along;
            let y = vertical ? along : button.y;
            if (root.edge === "bottom")
                y = dock.y + inset;
            else if (root.edge === "top")
                y = dock.y + root.dockSurface.height - inset - 1;
            else if (root.edge === "left")
                x = dock.x + root.dockSurface.width - inset - 1;
            else
                x = dock.x + inset;
            root.anchor.rect.x = Math.round(x);
            root.anchor.rect.y = Math.round(y);
            root.anchor.rect.width = 1;
            root.anchor.rect.height = 1;
        }
    }

    // Taken a moment after the popup shows. Taken at once, it was taken before
    // the popup had a surface to be listed by, so the grab held the dock alone
    // and a click anywhere on the popup counted as a click outside it.
    property bool grabbing: false

    // The first time the window is shown its first frame can reach the screen
    // at the wrong size, the panel drawn two or three times too large for a
    // frame. So that first time the window is shown empty, and the panel sets
    // off a couple of frames later: an empty frame at the wrong size shows as
    // nothing.
    property bool warmed: false

    onVisibleChanged: {
        if (root.visible) {
            grabDelay.restart();
            if (!root.warmed)
                warmUp.restart();
        } else {
            root.grabbing = false;
        }
    }

    Timer {
        id: warmUp
        interval: 48
        onTriggered: root.warmed = true
    }

    Timer {
        id: grabDelay
        interval: 50
        onTriggered: root.grabbing = root.visible
    }

    /** A press on a layer of this namespace, the dock's, is not a press outside. */
    property string ownNamespace: "quickshell:dock"

    // A press anywhere else closes the popup and still reaches what it landed
    // on, window focus included. Heard through the press-report plugin; a grab
    // stands in when it is not loaded, at the cost of eating that press.
    Connections {
        target: PointerPress
        // Armed with the grab's delay, so the press that opened the popup,
        // reported a moment later, is not taken for one outside it.
        enabled: root.open && root.grabbing && PointerPress.available

        function onPressed(kind, name) {
            if (kind !== "layer" || name !== root.ownNamespace)
                root.dismissRequested();
        }
    }

    HyprlandFocusGrab {
        windows: [root, root.dockWindow]
        active: root.open && root.grabbing && !PointerPress.available
        onCleared: root.dismissRequested()
    }

    // A panel on its way in or out is cut off at the dock's edge, so it comes
    // out from behind the dock instead of sliding over it. At rest nothing is
    // cut and the shadow falls whole.
    Item {
        readonly property real planeWidth: holder.width + 2 * root.padding
        readonly property real planeHeight: holder.height + 2 * root.padding
        readonly property real reach: root.shadowRoom - root.gap

        clip: root.motion === "panel" && surface.progress < 1
        x: root.edge === "left" ? reach : 0
        y: root.edge === "top" ? reach : 0
        width: root.edge === "right" ? root.shadowRoom + planeWidth + root.gap : root.edge === "left" ? root.width - reach : root.width
        height: root.edge === "bottom" ? root.shadowRoom + planeHeight + root.gap : root.edge === "top" ? root.height - reach : root.height

        ExFlyoutSurface {
            id: surface

            open: root.open && root.warmed
            edge: root.edge
            motion: root.motion
            radius: root.surfaceRadius
            restX: root.shadowRoom - parent.x
            restY: root.shadowRoom - parent.y
            width: holder.width + 2 * root.padding
            height: holder.height + 2 * root.padding

            Item {
                id: holder
                x: root.padding
                y: root.padding
                width: childrenRect.width
                height: childrenRect.height
            }
        }
    }
}
