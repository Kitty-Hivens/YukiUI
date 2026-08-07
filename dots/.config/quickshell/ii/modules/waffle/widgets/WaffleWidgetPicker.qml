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
                BoardState.pickerArea = Qt.rect(0, 0, 0, 0);
                BoardState.returning = false;
                if (BoardState.pickerWindow === pickerWindow)
                    BoardState.pickerWindow = null;
            }

            // Settles into place from just outside it, away from the board. Travelling
            // across the board on the way in meant walking over the cards.
            readonly property int travel: Math.round(BoardLooks.unit * 1.5)
            property real slide: pickerWindow.travel
            property real fade: 0

            ParallelAnimation {
                id: openAnim
                NumberAnimation {
                    target: pickerWindow
                    property: "slide"
                    to: 0
                    duration: 220
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.decelerate
                }
                NumberAnimation {
                    target: pickerWindow
                    property: "fade"
                    to: 1
                    duration: 140
                }
            }
            ParallelAnimation {
                id: closeAnim
                onFinished: pickerLoader.active = false
                NumberAnimation {
                    target: pickerWindow
                    property: "slide"
                    to: pickerWindow.travel
                    duration: 160
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Looks.transition.easing.bezierCurve.accelerate
                }
                NumberAnimation {
                    target: pickerWindow
                    property: "fade"
                    to: 0
                    duration: 140
                }
            }

            // The same pane the board is drawn on, so the two read as two panels
            // standing side by side rather than one panel and one rectangle.
            WPane {
                id: content
                x: BoardState.boardWidth + BoardLooks.gutter + pickerWindow.slide
                y: BoardState.boardTop
                opacity: pickerWindow.fade

                // Told to the board, so a press on this panel is not a press past it,
                // and so a card dragged over this panel is one being given back. Told
                // again whenever the panel moves: it starts beside a board that has
                // not said how wide it is yet, and it slides into place after that.
                function reportArea() {
                    BoardState.pickerArea = Qt.rect(content.x, content.y, content.width, content.height);
                }
                onXChanged: content.reportArea()
                onYChanged: content.reportArea()
                onWidthChanged: content.reportArea()
                onHeightChanged: content.reportArea()
                Component.onCompleted: {
                    content.reportArea();
                    BoardState.pickerWindow = pickerWindow;
                }

                contentItem: WidgetPicker {
                    implicitWidth: BoardLooks.pickerWidth
                    implicitHeight: Math.max(BoardState.boardHeight, BoardLooks.unit * 10)
                }
            }

            // The card being carried towards the board, drawn by the window so that
            // no pane masks it on the way.
            WidgetCardFor {
                id: carried
                visible: BoardState.carriedOffer !== ""
                cardId: BoardState.carriedOffer
                sample: true
                x: BoardState.carriedX
                y: BoardState.carriedY
                width: BoardState.carriedWidth
                height: BoardState.carriedHeight > 0 ? BoardState.carriedHeight : carried.implicitHeight
                opacity: 0.9
                z: 10
            }
        }
    }
}
