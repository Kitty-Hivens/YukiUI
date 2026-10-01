pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import qs.core
import qs.core.functions
import qs.waffle.looks

Loader {
    id: root

    required property var contentItem
    property real padding: Looks.radius.large - Looks.radius.medium
    property bool noSmoothClosing: !Config.options.waffles.tweaks.smootherMenuAnimations
    property bool closeOnFocusLost: true
    signal focusCleared()
    
    property Item anchorItem: parent
    property real visualMargin: 12
    readonly property bool barAtBottom: Config.options.waffles.bar.bottom
    property real ambientShadowWidth: 1

    onFocusCleared: {
        if (!root.closeOnFocusLost) return;
        root.close()
    }

    function grabFocus() { // Doesn't work
        item.grabFocus();
    }

    function close() {
        item.close();
    }

    function updateAnchor() {
        item?.anchor.updateAnchor();
    }

    active: false
    visible: active
    sourceComponent: PopupWindow {
        id: popupWindow
        visible: true
        Component.onCompleted: {
            // Taken once, never bound: see the anchor below.
            popupWindow.anchor.window = root.anchorItem?.QsWindow.window ?? null;
            openAnim.start();
        }

        // Anchored to the bar's window, with the button's box worked out each time
        // it is placed, and never to the button itself: a null anchor item makes
        // Quickshell 0.3.0 ask the null for its window and segfault, and a button
        // reads as null once it is destroyed.
        anchor {
            adjustment: PopupAdjustment.ResizeY | PopupAdjustment.SlideX
            gravity: root.barAtBottom ? Edges.Top : Edges.Bottom
            edges: root.barAtBottom ? Edges.Top : Edges.Bottom
            onAnchoring: {
                const target = root.anchorItem;
                if (!target)
                    return;
                const corner = target.mapToItem(null, 0, 0);
                popupWindow.anchor.rect.x = Math.round(corner.x);
                popupWindow.anchor.rect.y = Math.round(corner.y);
                popupWindow.anchor.rect.width = Math.max(1, Math.round(target.width));
                popupWindow.anchor.rect.height = Math.max(1, Math.round(target.height));
            }
        }

        HyprlandFocusGrab {
            id: focusGrab
            active: true
            windows: [popupWindow]
            onCleared: root.focusCleared();
        }

        function close() {
            if (root.noSmoothClosing) root.active = false;
            else closeAnim.start();
        }

        function grabFocus() {
            focusGrab.active = true; // Doesn't work
        }

        implicitWidth: realContent.implicitWidth + (root.ambientShadowWidth * 2) + (root.visualMargin * 2)
        implicitHeight: realContent.implicitHeight + (root.ambientShadowWidth * 2) + (root.visualMargin * 2)

        property real sourceEdgeMargin: -implicitHeight
        PropertyAnimation {
            id: openAnim
            target: popupWindow
            property: "sourceEdgeMargin"
            to: (root.ambientShadowWidth + root.visualMargin)
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.decelerate
        }
        SequentialAnimation {
            id: closeAnim
            PropertyAnimation {
                target: popupWindow
                property: "sourceEdgeMargin"
                to: -implicitHeight
                duration: 150
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Looks.transition.easing.bezierCurve.accelerate
            }
            ScriptAction {
                script: {
                    root.active = false;
                }
            }
        }

        color: "transparent"
        WAmbientShadow {
            target: realContent
        }
        
        Rectangle {
            id: realContent
            z: 1
            anchors {
                left: parent.left
                right: parent.right
                top: root.barAtBottom ? undefined : parent.top
                bottom: root.barAtBottom ? parent.bottom : undefined
                margins: root.ambientShadowWidth + root.visualMargin
                // Opening anim
                bottomMargin: root.barAtBottom ? popupWindow.sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                topMargin: root.barAtBottom ? (root.ambientShadowWidth + root.visualMargin) : popupWindow.sourceEdgeMargin
            }
            color: Looks.colors.bg1Base
            radius: Looks.radius.large

            // test
            implicitWidth: root.contentItem.implicitWidth + (root.padding * 2)
            implicitHeight: root.contentItem.implicitHeight + (root.padding * 2)

            children: [root.contentItem]
        }
    }
}
