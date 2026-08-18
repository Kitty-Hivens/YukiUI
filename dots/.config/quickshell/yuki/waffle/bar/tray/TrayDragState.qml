pragma Singleton

import QtQuick
import Quickshell

/**
 * What is being carried out of the tray, and where the places that can receive it
 * are.
 *
 * The same shape as the widget board's BoardState, and for the same reason: an
 * icon on its way somewhere is outside the surface it came from, so it cannot be
 * drawn by it -- the bar is 48 tall and clips anything lifted above it. A layer of
 * its own draws the icon, and since a DropArea does not reach across windows, the
 * targets publish their rectangles here in screen coordinates and the drop is
 * decided by arithmetic.
 */
Singleton {
    id: root

    /// The tray item under the cursor, or null when nothing is being carried.
    property var item: null
    readonly property bool active: root.item !== null

    /// Where the cursor is, in screen coordinates.
    property real pointerX: 0
    property real pointerY: 0
    /// Where the cursor sat inside the icon when it was picked up, so the icon
    /// keeps its grip rather than jumping to centre itself.
    property real grabX: 0
    property real grabY: 0

    /// What letting go right now would do: "unpin" to hide the icon away, "pin" to
    /// bring it back out, or nothing at all. The source sets it as the pointer
    /// moves, because only the source knows which way it is going.
    property string dropAction: ""
    readonly property bool willDrop: root.dropAction !== ""

    /// Where the insertion line belongs, in the bar window's coordinates, or -1 when
    /// the pointer is not over a place that would take the icon. Published by the row
    /// that knows its own gaps; drawn by the layer, because the line stands taller
    /// than the bar and would be cut off inside it.
    property real insertX: -1

    /// Published by whoever draws them, in screen coordinates.
    property rect hiddenArea: Qt.rect(0, 0, 0, 0)
    property rect pinnedArea: Qt.rect(0, 0, 0, 0)

    function inside(area, x, y) {
        return area.width > 0 && x >= area.x && x <= area.x + area.width
            && y >= area.y && y <= area.y + area.height;
    }

    readonly property bool overHidden: root.inside(root.hiddenArea, root.pointerX, root.pointerY)
    readonly property bool overPinned: root.inside(root.pinnedArea, root.pointerX, root.pointerY)

    function begin(trayItem, screenX, screenY, insideX, insideY) {
        root.grabX = insideX;
        root.grabY = insideY;
        root.pointerX = screenX;
        root.pointerY = screenY;
        root.item = trayItem;
    }

    function moveTo(screenX, screenY) {
        root.pointerX = screenX;
        root.pointerY = screenY;
    }

    function clear() {
        root.item = null;
        root.dropAction = "";
        root.insertX = -1;
    }
}
