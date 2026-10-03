import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import Quickshell

PopupWindow {
    id: root

    ///////////////////// Properties ////////////////////
    required property bool tasksHovered
    property var appEntry
    property Item anchorItem

    //////////////////// Functions ////////////////////
    function close() { // Closing doesn't animate, not sure if they're just lazy or it's intentional
        marginBehavior.enabled = false;
        root.visible = false;
        // Dropped, or the hidden popup keeps a screencopy of every window of the
        // last application hovered for as long as the bar lives.
        root.appEntry = null;
    }

    function open() {
        marginBehavior.enabled = true;
        root.visible = true;
        contentItem.opacity = 0;
        fadeIn.restart();
    }

    function show(appEntry: var, button: Item) {
        root.appEntry = appEntry;
        root.anchorItem = button;
        // Read once, as it opens, and never bound: the bar window is torn down
        // under a fullscreen game, and a binding that reads it back from inside
        // that teardown is what used to segfault the shell.
        root.anchor.window = button.QsWindow.window;
        root.anchor.updateAnchor();
        root.open();
    }

    ///////////////////// Internals /////////////////////
    readonly property bool bottom: Config.options.waffles.bar.bottom
    property real visualMargin: 12
    property real ambientShadowWidth: 1

    visible: false
    color: "transparent"
    implicitWidth: contentItem.implicitWidth + ambientShadowWidth + (visualMargin * 2)
    implicitHeight: contentItem.implicitHeight + ambientShadowWidth + (visualMargin * 2)
    // Anchored to the bar's window, read off the button as it is shown, with the button's
    // box worked out as the popup is shown. Never to the button as an item: the
    // buttons are rebuilt whenever the workspace changes, the reference to a
    // destroyed one reads as null, and a null anchor item makes Quickshell
    // 0.3.0 ask that null item for its window, which segfaults the shell.
    anchor {
        adjustment: PopupAdjustment.Slide
        gravity: bottom ? Edges.Top : Edges.Bottom
        edges: bottom ? Edges.Top : Edges.Bottom
        onAnchoring: {
            if (!root.anchorItem)
                return;
            const corner = root.anchorItem.mapToItem(null, 0, 0);
            root.anchor.rect.x = Math.round(corner.x);
            root.anchor.rect.y = Math.round(corner.y);
            root.anchor.rect.width = Math.max(1, Math.round(root.anchorItem.width));
            root.anchor.rect.height = Math.max(1, Math.round(root.anchorItem.height));
        }
    }

    NumberAnimation {
        id: fadeIn
        target: contentItem
        property: "opacity"
        from: 0
        to: 1
        duration: 120
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Looks.transition.easing.bezierCurve.decelerate
    }

    Timer {
        interval: 250
        running: root.visible && !hoverChecker.containsMouse && !root.tasksHovered
        onTriggered: {
            root.close();
        }
    }

    // Content
    MouseArea {
        id: hoverChecker
        anchors.fill: parent
        hoverEnabled: true

        // Shadow
        WAmbientShadow {
            target: contentItem
        }

        Rectangle {
            id: contentItem
            property real sourceEdgeMargin: root.visible ? (root.ambientShadowWidth + root.visualMargin) : -root.implicitHeight
            Behavior on sourceEdgeMargin {
                id: marginBehavior
                animation: Looks.transition.enter.createObject(this)
            }
            anchors {
                left: parent.left
                right: parent.right
                top: root.bottom ? undefined : parent.top
                bottom: root.bottom ? parent.bottom : undefined
                margins: root.ambientShadowWidth + root.visualMargin
                // Opening anim
                bottomMargin: root.bottom ? sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                topMargin: root.bottom ? (root.ambientShadowWidth + root.visualMargin) : sourceEdgeMargin
            }
            color: Looks.colors.bg1Base
            radius: Looks.radius.large

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: contentItem.width
                    height: contentItem.height
                    radius: contentItem.radius
                }
            }

            // Testing
            implicitHeight: Math.min(158, windowsRow.implicitHeight)
            implicitWidth: windowsRow.implicitWidth

            RowLayout {
                id: windowsRow
                anchors.fill: parent

                Repeater {
                    model: ScriptModel {
                        // The windows the button has on the workspace in use, read
                        // from the button so the row follows them while it is open.
                        //
                        // Emptied while hidden, so a hidden popup keeps no capture of
                        // those windows.
                        values: root.visible ? (root.anchorItem?.windows ?? []) : []
                    }
                    delegate: WindowPreview {
                        required property var modelData
                        toplevel: modelData
                        onPicked: root.close()
                    }
                }
            }
        }
    }
}
