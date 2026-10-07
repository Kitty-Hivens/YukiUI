pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core
import qs.experimental.looks

// A widget of the game bar: a plate with its name along the top, moved by
// dragging the name, and closed from there. Its contents go under the name.
// Where it is left is kept, and it comes back there, held on the screen.
Item {
    id: frame

    required property var bar
    required property string key
    required property string title
    required property string glyph
    /** Where it goes before it has ever been moved. */
    property real defaultX: 0
    property real defaultY: 0

    default property alias content: column.data

    readonly property var saved: Persistent.states.gameBar[frame.key]
    readonly property real wantedX: frame.saved.x >= 0 ? frame.saved.x : frame.defaultX
    readonly property real wantedY: frame.saved.y >= 0 ? frame.saved.y : frame.defaultY

    visible: frame.bar.isShown(frame.key)
    x: Math.round(Math.max(0, Math.min((frame.parent?.width ?? 0) - frame.width, frame.wantedX)))
    y: Math.round(Math.max(0, Math.min((frame.parent?.height ?? 0) - frame.height, frame.wantedY)))
    implicitWidth: column.implicitWidth + 2 * ExLooks.spacing.m
    implicitHeight: column.implicitHeight + ExLooks.spacing.xs + ExLooks.spacing.m

    ExSurface {
        anchors.fill: parent
        radius: ExLooks.radius.menu
        elevation: 2

        // A click on the widget between its controls is not a click beside it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }
    }

    ColumnLayout {
        id: column

        x: ExLooks.spacing.m
        y: ExLooks.spacing.xs
        width: frame.width - 2 * ExLooks.spacing.m
        spacing: ExLooks.spacing.s

        Item {
            id: handle

            Layout.fillWidth: true
            implicitWidth: titleRow.implicitWidth
            implicitHeight: 36

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
                id: titleRow

                anchors.fill: parent
                spacing: ExLooks.spacing.s

                ExGlyph {
                    text: frame.glyph
                    size: 18
                    color: ExLooks.colors.textDim
                }
                ExText {
                    Layout.fillWidth: true
                    text: frame.title
                    role: "label"
                }
                ExToolButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    glyph: "close"
                    onClicked: frame.bar.setShown(frame.key, false)
                }
            }
        }
    }
}
