pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core
import qs.experimental.looks

// A widget of the game bar: a panel as the dock's flyouts are, with its name
// along the top, moved by dragging the name and closed from there. Its
// contents go under the name. Where it is left is kept, and it comes back
// there, held on the screen. Every widget is as wide as the others.
Item {
    id: frame

    required property var bar
    required property string key
    required property string title
    required property string glyph
    /** Where it goes before it has ever been moved. */
    property real defaultX: 0
    property real defaultY: 0

    /** How wide what a widget holds is, the same for all of them. */
    readonly property real contentWidth: 336

    /** Its place among the widgets coming in, each a moment after the one before. */
    property int order: 0
    /** The bar is on screen, and the widget may come in. */
    property bool shown: false
    // From below and faded (0) to in place (1), each time it comes on screen.
    property real arrival: 0
    function arrive() {
        if (!frame.shown || !frame.visible)
            return;
        frame.arrival = 0;
        entrance.restart();
    }
    onVisibleChanged: frame.arrive()
    onShownChanged: frame.arrive()
    SequentialAnimation {
        id: entrance

        PauseAnimation {
            duration: frame.order * 40
        }
        NumberAnimation {
            target: frame
            property: "arrival"
            to: 1
            duration: ExLooks.motion.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ExLooks.motion.decelerate
        }
    }
    opacity: frame.arrival
    transform: Translate {
        y: (1 - frame.arrival) * 16
    }

    default property alias content: column.data

    readonly property var saved: Persistent.states.gameBar[frame.key]
    readonly property real wantedX: frame.saved.x >= 0 ? frame.saved.x : frame.defaultX
    readonly property real wantedY: frame.saved.y >= 0 ? frame.saved.y : frame.defaultY

    visible: frame.bar.isShown(frame.key)
    x: Math.round(Math.max(0, Math.min((frame.parent?.width ?? 0) - frame.width, frame.wantedX)))
    y: Math.round(Math.max(0, Math.min((frame.parent?.height ?? 0) - frame.height, frame.wantedY)))
    implicitWidth: frame.contentWidth + 2 * ExLooks.spacing.l
    implicitHeight: column.implicitHeight + 2 * ExLooks.spacing.l - ExLooks.spacing.xs

    ExSurface {
        anchors.fill: parent
        radius: ExLooks.radius.panel
        elevation: 1

        // A click on the widget between its controls is not a click beside it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }
    }

    ColumnLayout {
        id: column

        x: ExLooks.spacing.l
        // The close button's plate reaches above the line of the name.
        y: ExLooks.spacing.l - ExLooks.spacing.xs
        width: frame.contentWidth
        spacing: ExLooks.spacing.m

        Item {
            id: handle

            Layout.fillWidth: true
            implicitHeight: 32

            DragHandler {
                id: drag

                target: frame
                xAxis.minimum: 0
                xAxis.maximum: (frame.parent?.width ?? 0) - frame.width
                yAxis.minimum: 0
                yAxis.maximum: (frame.parent?.height ?? 0) - frame.height
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: {
                    if (drag.active)
                        return;
                    frame.saved.x = Math.round(frame.x);
                    frame.saved.y = Math.round(frame.y);
                    // The drag wrote the place over the binding, and the place
                    // just kept is where the binding now leads.
                    frame.x = Qt.binding(() => Math.round(Math.max(0, Math.min((frame.parent?.width ?? 0) - frame.width, frame.wantedX))));
                    frame.y = Qt.binding(() => Math.round(Math.max(0, Math.min((frame.parent?.height ?? 0) - frame.height, frame.wantedY))));
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: ExLooks.spacing.s

                ExGlyph {
                    text: frame.glyph
                    size: 20
                    color: ExLooks.colors.accent
                }
                ExText {
                    Layout.fillWidth: true
                    text: frame.title
                    role: "label"
                    font.weight: ExLooks.font.weightTitle
                    font.pixelSize: ExLooks.font.body
                }
                ExToolButton {
                    Layout.rightMargin: -ExLooks.spacing.xs
                    implicitWidth: 32
                    implicitHeight: 32
                    glyph: "close"
                    onClicked: frame.bar.setShown(frame.key, false)
                }
            }
        }
    }
}
