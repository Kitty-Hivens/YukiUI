pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

import qs
import qs.core.services
import qs.experimental.looks

// Drawing the part of a screen to share, on every screen at once. The screen
// dims except for the rectangle being drawn, which shows its size as it grows.
// Letting go shares it, and Escape or a right click goes back to the picker.
Scope {
    id: root

    Variants {
        model: GlobalStates.screenShareRegionOpen ? Quickshell.screens : []

        PanelWindow {
            id: window

            required property var modelData

            // Where the drag started and where the pointer is, in this screen.
            property point start: Qt.point(0, 0)
            property point end: Qt.point(0, 0)
            property bool drawing: false
            readonly property rect selection: Qt.rect(Math.min(window.start.x, window.end.x), Math.min(window.start.y, window.end.y),
                Math.abs(window.end.x - window.start.x), Math.abs(window.end.y - window.start.y))
            readonly property bool hasSelection: window.selection.width >= 8 && window.selection.height >= 8

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:regionSelection"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function back() {
                GlobalStates.screenShareRegionOpen = false;
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: window.back()

                // The dimming, in four pieces round the selection so that what
                // is inside it shows as it is.
                readonly property color veil: "#73000000"

                Rectangle {
                    x: 0
                    y: 0
                    width: parent.width
                    height: window.hasSelection ? window.selection.y : parent.height
                    color: parent.veil
                }
                Rectangle {
                    visible: window.hasSelection
                    x: 0
                    y: window.selection.y + window.selection.height
                    width: parent.width
                    height: parent.height - y
                    color: parent.veil
                }
                Rectangle {
                    visible: window.hasSelection
                    x: 0
                    y: window.selection.y
                    width: window.selection.x
                    height: window.selection.height
                    color: parent.veil
                }
                Rectangle {
                    visible: window.hasSelection
                    x: window.selection.x + window.selection.width
                    y: window.selection.y
                    width: parent.width - x
                    height: window.selection.height
                    color: parent.veil
                }

                Rectangle {
                    visible: window.hasSelection
                    x: window.selection.x - 1
                    y: window.selection.y - 1
                    width: window.selection.width + 2
                    height: window.selection.height + 2
                    color: "transparent"
                    border.width: 2
                    border.color: ExLooks.colors.accent
                }

                // The size, just outside the corner the pointer is at.
                Rectangle {
                    visible: window.hasSelection
                    x: Math.min(parent.width - width - 8, window.selection.x + window.selection.width - width)
                    y: window.selection.y + window.selection.height + 8 + height > parent.height
                        ? window.selection.y - height - 8 : window.selection.y + window.selection.height + 8
                    width: sizeLabel.implicitWidth + 2 * ExLooks.spacing.s
                    height: 26
                    radius: ExLooks.radius.menuItem
                    color: ExLooks.colors.accent

                    ExText {
                        id: sizeLabel
                        anchors.centerIn: parent
                        text: `${Math.round(window.selection.width)} × ${Math.round(window.selection.height)}`
                        role: "label"
                        color: ExLooks.colors.accentInk
                    }
                }

                // What to do, until something is drawn.
                ExSurface {
                    visible: !window.drawing
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.08
                    width: hint.implicitWidth + 2 * ExLooks.spacing.l
                    height: 40
                    radius: height / 2
                    elevation: 1

                    ExText {
                        id: hint
                        anchors.centerIn: parent
                        text: Translation.tr("Drag to choose the part of the screen to share. Esc goes back")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.CrossCursor

                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            window.back();
                            return;
                        }
                        window.start = Qt.point(event.x, event.y);
                        window.end = window.start;
                        window.drawing = true;
                    }
                    onPositionChanged: event => {
                        if (window.drawing)
                            window.end = Qt.point(Math.max(0, Math.min(width, event.x)), Math.max(0, Math.min(height, event.y)));
                    }
                    onReleased: event => {
                        if (event.button !== Qt.LeftButton || !window.drawing)
                            return;
                        window.drawing = false;
                        if (!window.hasSelection)
                            return;
                        const area = window.selection;
                        ScreenShare.submitRegion(window.modelData.name, area.x, area.y, area.width, area.height);
                    }
                }
            }
        }
    }
}
