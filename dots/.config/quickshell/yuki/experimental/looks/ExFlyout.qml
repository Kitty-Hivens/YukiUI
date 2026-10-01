import QtQuick

/**
 * A flyout drawn inside something that covers the whole screen: the gallery's
 * stand-in screens. The desktop itself uses ExPopup, which is a window of its
 * own; both move the same way, through ExFlyoutSurface.
 *
 * Where the panel stands comes from two rectangles: the dock decides how far
 * it sits from the screen edge, the button that opened it decides where along
 * that edge.
 */
Item {
    id: root

    property bool open: false
    property string edge: "bottom"
    property rect dockRect
    property rect anchorRect
    property real padding: ExLooks.spacing.l
    property real previewProgress: -1

    default property alias content: holder.data

    signal dismissRequested

    readonly property real margin: ExLooks.spacing.s

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    visible: surface.progress > 0
    focus: open
    Keys.onEscapePressed: root.dismissRequested()

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onPressed: mouse => {
            root.dismissRequested();
            // Everything except the button that opened the panel still gets
            // the press. That button would read it as a second click and open
            // the panel again right after it closed.
            const r = root.anchorRect;
            mouse.accepted = mouse.x >= r.x && mouse.x < r.x + r.width && mouse.y >= r.y && mouse.y < r.y + r.height;
        }
    }

    ExFlyoutSurface {
        id: surface

        open: root.open
        edge: root.edge
        previewProgress: root.previewProgress
        width: holder.width + 2 * root.padding
        height: holder.height + 2 * root.padding
        elevation: 2
        restX: root.edge === "left" ? root.dockRect.x + root.dockRect.width + root.margin
            : root.edge === "right" ? root.dockRect.x - root.margin - width
            : root.clamp(root.anchorRect.x + root.anchorRect.width / 2 - width / 2, root.margin, root.width - root.margin - width)
        restY: root.edge === "bottom" ? root.dockRect.y - root.margin - height
            : root.edge === "top" ? root.dockRect.y + root.dockRect.height + root.margin
            : root.clamp(root.anchorRect.y + root.anchorRect.height / 2 - height / 2, root.margin, root.height - root.margin - height)

        Item {
            id: holder
            x: root.padding
            y: root.padding
            width: childrenRect.width
            height: childrenRect.height
        }
    }
}
