import qs.core
import qs.core.services
import QtQuick

/**
 * A convenience MouseArea for handling drag events.
 */
MouseArea {
    id: root
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    property bool interactive: true
    property bool automaticallyReset: true
    /// How far the pointer travels before a press counts as a drag. The list a
    /// notification sits in waits for the system's distance before it takes a
    /// gesture for itself, so an item that answered the first pixel was fighting it
    /// for every press: the card moved while the list scrolled. Set to 0 where the
    /// gesture is the only thing on offer, as in the region selector.
    property real dragThreshold: Qt.styleHints.startDragDistance
    /// Which way a gesture has to leave to belong to this manager. A press that
    /// leaves the other way is never taken up, so the list underneath gets it
    /// straight away instead of the two trading it back and forth.
    property int acceptedAxis: Qt.Horizontal | Qt.Vertical
    readonly property real dragDiffX: _dragDiffX
    readonly property real dragDiffY: _dragDiffY
    property real startX: 0
    property real startY: 0
    property real regionTopLeftX: Math.min(startX, startX + _dragDiffX)
    property real regionTopLeftY: Math.min(startY, startY + _dragDiffY)
    property real regionWidth: Math.abs(_dragDiffX)
    property real regionHeight: Math.abs(_dragDiffY)

    signal dragPressed(diffX: real, diffY: real)
    signal dragReleased(diffX: real, diffY: real)
    
    property bool dragging: false
    property real _dragDiffX: 0
    property real _dragDiffY: 0

    function resetDrag() {
        _dragDiffX = 0
        _dragDiffY = 0
    }

    onPressed: (mouse) => {
        if (!root.interactive) {
            if (mouse.button === Qt.LeftButton) {
                mouse.accepted = false;
            }
            return;
        }
        if (mouse.button === Qt.LeftButton) {
            startX = mouse.x
            startY = mouse.y
        }
    }
    onReleased: (mouse) => {
        if (!root.interactive) {
            return;
        }
        dragging = false
        root.preventStealing = false;
        root.dragReleased(_dragDiffX, _dragDiffY);
        if (root.automaticallyReset) {
            root.resetDrag();
        }
    }
    onPositionChanged: (mouse) => {
        if (!root.interactive) {
            return;
        }
        if (mouse.buttons & Qt.LeftButton) {
            const diffX = mouse.x - startX;
            const diffY = mouse.y - startY;
            if (!root.dragging) {
                // The distance decides where a drag begins, and the direction
                // decides whose it is.
                if (Math.sqrt(diffX * diffX + diffY * diffY) < root.dragThreshold)
                    return;
                const leaving = Math.abs(diffX) >= Math.abs(diffY) ? Qt.Horizontal : Qt.Vertical;
                if (!(root.acceptedAxis & leaving))
                    return;
                // Held for the rest of the gesture: a list above this would take the
                // grab the moment the pointer wandered across it, and the card would
                // snap back in the middle of being swiped away.
                root.preventStealing = true;
            }
            root._dragDiffX = diffX;
            root._dragDiffY = diffY;
            root.dragPressed(_dragDiffX, _dragDiffY);
            root.dragging = true;
        }
    }
    onCanceled: (mouse) => {
        if (!root.interactive) {
            return;
        }
        released(mouse);
    }
}
