import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

// The widgets on offer, in a window of their own beside the board: two panels side
// by side rather than one grown wider.
Scope {
    id: root

    Loader {
        id: pickerLoader

        // Kept alive past the moment editing ends, so the panel can go back behind
        // the board instead of blinking out of existence.
        readonly property bool shown: GlobalStates.widgetsOpen && BoardState.editing
        active: false
        onShownChanged: {
            if (pickerLoader.shown)
                pickerLoader.active ? pickerLoader.item.open() : pickerLoader.active = true;
            else if (pickerLoader.item)
                pickerLoader.item.close();
        }
        Component.onCompleted: pickerLoader.active = pickerLoader.shown

        sourceComponent: PanelWindow {
            id: pickerWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wWidgetPicker"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            // The window spans the screen while the panel inside it stands beside the
            // board: a widget carried towards the board would otherwise be cut off at
            // the edge of a window only as wide as the panel.
            anchors {
                bottom: true
                top: true
                left: true
                right: true
            }

            // Input only where the panel is drawn, and nowhere at all once it is on
            // its way out: the press that ended editing must not be eaten twice.
            property bool closing: false
            Region {
                id: noInput
            }
            Region {
                id: panelOnly
                item: content
            }
            mask: pickerWindow.closing ? noInput : panelOnly

            function open() {
                closeAnim.stop();
                pickerWindow.closing = false;
                openAnim.start();
            }
            function close() {
                openAnim.stop();
                pickerWindow.closing = true;
                pickerWindow.dropCarried();
                closeAnim.start();
            }

            // A drag ends by being let go, and a window that goes away underneath one
            // never gets there: the cell marked out on the board would stay marked.
            function dropCarried() {
                BoardState.carriedOffer = "";
                BoardState.aimDrop(null);
            }

            Component.onCompleted: pickerWindow.open()
            Component.onDestruction: {
                pickerWindow.dropCarried();
                if (BoardState.pickerWindow === pickerWindow)
                    BoardState.pickerWindow = null;
            }

            // Comes out from behind the board, and goes back the same way.
            property real slide: -BoardLooks.pickerWidth
            NumberAnimation {
                id: openAnim
                target: pickerWindow
                property: "slide"
                to: 0
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
            }
            NumberAnimation {
                id: closeAnim
                target: pickerWindow
                property: "slide"
                to: -BoardLooks.pickerWidth
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Looks.transition.easing.bezierCurve.easeOut
                onFinished: pickerLoader.active = false
            }

            // The same pane the board is drawn on, so the two read as two panels
            // standing side by side rather than one panel and one rectangle.
            WPane {
                id: content
                x: BoardState.boardWidth + BoardLooks.gutter + pickerWindow.slide
                y: BoardState.boardTop
                opacity: 1 + pickerWindow.slide / BoardLooks.pickerWidth

                // Told to the board, so a press on this panel is not a press past it.
                Component.onCompleted: BoardState.pickerWindow = pickerWindow

                contentItem: WidgetPicker {
                    implicitWidth: BoardLooks.pickerWidth
                    implicitHeight: Math.max(BoardState.boardHeight, BoardLooks.unit * 10)
                }
            }

            // The card being carried towards the board, drawn by the window so that
            // no pane masks it on the way.
            WidgetCardFor {
                visible: BoardState.carriedOffer !== ""
                cardId: BoardState.carriedOffer
                sample: true
                x: BoardState.carriedX
                y: BoardState.carriedY
                width: BoardState.carriedWidth
                opacity: 0.9
                z: 10
            }
        }
    }
}
