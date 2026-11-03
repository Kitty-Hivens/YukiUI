import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.core.services
import qs.blueberry

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
    // Room around the plane for its shadow.
    readonly property real shadowRoom: 32
    /**
     * The room on the dock's side, which is only the gap: the window ends at
     * the dock's edge. With the shadow's room there too it reached over the
     * top of the dock, and appearing under a pointer resting on the button it
     * came from it was given the pointer before its mask said otherwise. The
     * compositor works that out again only when the pointer moves, so a
     * second click on the button without moving the mouse landed on the
     * window's empty edge and was lost. The shadow on that side falls behind
     * the dock's edge as it did.
     */
    readonly property real nearRoom: root.gap
    readonly property bool vertical: root.edge === "left" || root.edge === "right"

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

    /** The plane's height, following its content as that animates. */
    readonly property real planeHeight: holder.height + 2 * root.padding
    // The window is not resized with every frame of a plane growing or
    // shrinking: a popup window changes size only once the compositor has
    // answered, and nothing was drawn meanwhile, so a panel animating its
    // height covered most of the way in one jump. Growing, the window takes
    // room to spare at once. Shrinking, it keeps its size while the plane
    // shrinks inside it, and is cut down once the plane has been still a
    // moment. The spare room is transparent and takes no pointer.
    //
    // That needs one edge of the plane to stand still. Against a dock along
    // the top or the bottom it is the edge facing the dock. Beside a dock at
    // a side the window was centred on its button and grew both ways, so it
    // was resized every frame instead. There the plane now grows one way, see
    // `growth`.
    //
    // A window growing up is not resized at all while it shows, but takes all
    // the room above it as it opens. Its top edge moves as it grows, and
    // Hyprland moves a popup the moment it sends the new size, not once the
    // new frame arrives, so the frame before was drawn that much higher until
    // the shell drew again: a frame on an idle machine, a good part of a
    // second on a busy one.
    /**
     * Beside a dock at a side, which way the plane grows: "down" from its top,
     * or "up" from its bottom, towards the longer stretch of the dock from
     * where it opened. Decided as it is placed.
     */
    property string growth: "down"
    readonly property bool growsUp: root.vertical && root.growth === "up"
    /** Whether the window's top edge is the one that moves: over a dock at the bottom, or growing up beside one at a side. */
    readonly property bool topMoves: root.edge === "bottom" || root.growsUp
    /** From the bottom of the window to the top of the screen, as last placed. */
    property real roomAbove: 0
    readonly property real spareRoom: 160
    property real heldPlaneHeight: 0
    onPlaneHeightChanged: {
        if (root.planeHeight > root.heldPlaneHeight) {
            heldTrim.stop();
            root.heldPlaneHeight = root.planeHeight + (root.visible ? root.spareRoom : 0);
            if (root.visible)
                heldTrim.restart();
        } else if (root.planeHeight < root.heldPlaneHeight) {
            heldTrim.restart();
        }
    }
    Timer {
        id: heldTrim
        interval: 400
        onTriggered: root.heldPlaneHeight = root.planeHeight
    }

    implicitWidth: holder.width + 2 * root.padding + root.shadowRoom + (root.vertical ? root.nearRoom : root.shadowRoom)
    readonly property real neededHeight: Math.max(root.heldPlaneHeight, root.planeHeight) + root.shadowRoom + (root.vertical ? root.shadowRoom : root.nearRoom)
    implicitHeight: root.topMoves && root.visible ? Math.max(root.roomAbove, root.neededHeight) : root.neededHeight
    // Only the plate takes the pointer, the room for its shadow letting
    // clicks through to whatever lies under it.
    mask: Region {
        item: surface
    }

    anchor {
        window: root.dockWindow
        // Kept on screen here rather than by the compositor. Sliding the window
        // back counts the shadow room around the plane as part of it, so a
        // popup near a corner stopped short of it by that much.
        adjustment: PopupAdjustment.None
        // Beside a side dock the window hangs from the plane's edge that stands
        // still, so it grows the other way.
        edges: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom
            : (root.edge === "left" ? Edges.Right : Edges.Left) | (root.growsUp ? Edges.Top : Edges.Bottom)
        gravity: root.edge === "bottom" ? Edges.Top : root.edge === "top" ? Edges.Bottom
            : (root.edge === "left" ? Edges.Right : Edges.Left) | (root.growsUp ? Edges.Top : Edges.Bottom)
        // A point, not a box: along the dock it is the middle of the button,
        // across it the dock's inner edge, where the window begins.
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
            const inset = root.nearRoom - root.gap;
            const margin = root.dockWindow.detached ? 0 : root.gap;
            const vertical = root.edge === "left" || root.edge === "right";
            const half = (vertical ? surface.height : surface.width) / 2;
            let start = (vertical ? dock.y : dock.x) + margin + half;
            let end = (vertical ? dock.y + root.dockSurface.height : dock.x + root.dockSurface.width) - margin - half;
            // Longer than the dock, an island's say, it is kept on the screen
            // instead, which the dock's window spans.
            if (end < start) {
                const total = vertical ? root.dockWindow.height : root.dockWindow.width;
                start = root.gap + half;
                end = Math.max(start, total - root.gap - half);
            }
            const along = Math.max(start, Math.min(end, vertical ? button.y : button.x));
            let x = vertical ? button.x : along;
            let y = vertical ? along : button.y;
            // Beside a side dock: towards the longer stretch of the dock, and
            // the window's edge put at the plane's edge that stands still.
            if (vertical) {
                const middle = dock.y + root.dockSurface.height / 2;
                root.growth = along > middle ? "up" : "down";
                y = root.growth === "up" ? along + half + root.shadowRoom : along - half - root.shadowRoom;
            }
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
            // The dock's window stands on the bottom of its screen, and the
            // popup's window hangs above this point when its top is the edge
            // that moves.
            root.roomAbove = Math.round(y) + (root.dockWindow.screen?.height ?? 0) - root.dockWindow.height;
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
            // Whether presses are reported is asked again each time: the
            // plugin can be unloaded by hand, which nothing announces.
            PointerPress.check();
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
    // on, window focus included. Heard through the press-report plugin. A grab
    // stands in when it is not loaded, at the cost of eating that press.
    Connections {
        target: PointerPress
        // Armed with the grab's delay, so the press that opened the popup,
        // reported a moment later, is not taken for one outside it.
        enabled: root.open && root.grabbing && PointerPress.available

        function onPressed(kind, name) {
            // Every screen's dock has the same namespace, and a press on
            // another screen's dock is a press outside this one.
            const elsewhere = Hyprland.focusedMonitor?.name !== root.dockWindow.screen?.name;
            if (kind !== "layer" || name !== root.ownNamespace || elsewhere)
                root.dismissRequested();
        }
    }

    // One flyout at a time across every dock. A dock shuts its own others
    // when one opens, and this does it for the docks of the other screens.
    onOpenChanged: {
        if (root.open)
            ExStates.openPopup = root;
        else if (ExStates.openPopup === root)
            ExStates.openPopup = null;
    }
    Connections {
        target: ExStates
        function onOpenPopupChanged() {
            if (root.open && ExStates.openPopup !== root)
                root.dismissRequested();
        }
    }

    // The button it came out of gone, an application's last window closed
    // or a tray icon whose program quit, there is nothing left to belong to.
    onOpenerChanged: {
        if (root.open && !root.opener)
            root.dismissRequested();
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
        readonly property real reach: root.nearRoom - root.gap

        clip: root.motion === "panel" && surface.progress < 1
        x: root.edge === "left" ? reach : 0
        y: root.edge === "top" ? reach : 0
        // Against a dock at the bottom the plane hangs from the window's
        // bottom, whatever room the window keeps above it. Anchored, it moves
        // in the very frame the window changes size. Placed from the height
        // the window reports, it stood at the top of a window that had grown
        // for one frame, before the height caught up.
        // Growing up beside a side dock, the same: hung from the window's
        // bottom, which is what stands still on the screen.
        anchors.bottom: root.edge === "bottom" || root.growsUp ? parent.bottom : undefined
        anchors.bottomMargin: root.edge === "bottom" ? reach : 0
        width: root.edge === "right" ? root.shadowRoom + planeWidth + root.gap : root.edge === "left" ? root.width - reach : root.width
        height: root.edge === "bottom" ? root.shadowRoom + planeHeight + root.gap : root.edge === "top" ? root.height - reach
            : root.growsUp ? planeHeight + 2 * root.shadowRoom : root.height

        ExFlyoutSurface {
            id: surface

            open: root.open && root.warmed
            edge: root.edge
            motion: root.motion
            radius: root.surfaceRadius
            restX: (root.edge === "left" ? root.nearRoom : root.shadowRoom) - parent.x
            restY: root.edge === "bottom" || root.growsUp ? root.shadowRoom : (root.edge === "top" ? root.nearRoom : root.shadowRoom) - parent.y
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
