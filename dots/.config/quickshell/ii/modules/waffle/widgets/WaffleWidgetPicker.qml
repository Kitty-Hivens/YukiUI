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
        active: GlobalStates.widgetsOpen && BoardState.editing

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

            // Input only where the panel is drawn.
            mask: Region {
                item: content
            }

            Component.onCompleted: openAnim.start()
            Component.onDestruction: {
                if (BoardState.pickerWindow === pickerWindow)
                    BoardState.pickerWindow = null;
            }

            // Comes out from behind the board.
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

            // The same pane the board is drawn on, so the two read as two panels
            // standing side by side rather than one panel and one rectangle.
            WPane {
                id: content
                x: BoardState.boardWidth + BoardLooks.gutter + pickerWindow.slide
                y: BoardState.boardTop
                opacity: 1 + pickerWindow.slide / BoardLooks.pickerWidth

                // Told to whoever carries a widget out of here, so it can be placed in
                // the board's own coordinates, and to the board, so a press on this
                // panel is not a press past it.
                onXChanged: BoardState.pickerLeft = content.x
                Component.onCompleted: {
                    BoardState.pickerLeft = content.x;
                    BoardState.pickerWindow = pickerWindow;
                }

                contentItem: WidgetPicker {
                    implicitWidth: BoardLooks.pickerWidth
                    implicitHeight: BoardState.boardHeight
                }
            }
        }
    }
}
