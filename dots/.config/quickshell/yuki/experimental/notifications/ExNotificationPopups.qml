import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs.core
import qs.core.services
import qs.experimental.looks

// Notifications as they arrive, stacked at the right edge next to the status
// block on the screen in focus: over the dock, or under it when the dock is at
// the top. The dock's exclusive zone keeps them clear of it.
//
// The window takes the whole height beside the dock and keeps it, and only
// the cards take the pointer. Sized to the cards instead, it changed size as
// they came and went, the list laid its cards out again from the new bottom,
// and with them moving the size changed once more: the stack jumped back and
// forth by ten or twenty pixels a frame while anything was on its way.
//
// The list is laid out from the top and moved so its end meets the dock. Laid
// out from the bottom, a card that reached its full height a moment after it
// was made grew downwards, under the dock, until something else moved the
// list.
PanelWindow {
    id: root

    readonly property bool dockAtTop: Config.options.experimental.dock.edge === "top"
    readonly property real shadowRoom: 24
    // Up while there is anything to show, and a moment after the last one goes,
    // so it can leave the way it came. Raised only once the list was already
    // empty, the window was gone for a frame before it came back for the way
    // out.
    property bool holding: false
    // The window has its height. It comes up without one, and the list,
    // placed from the bottom of nothing, flew down from the top of the screen.
    property bool sized: false
    onHeightChanged: {
        if (root.height > 0)
            Qt.callLater(() => root.sized = root.visible && root.height > 0);
    }
    onVisibleChanged: {
        if (!root.visible)
            root.sized = false;
        else if (root.height > 0)
            Qt.callLater(() => root.sized = root.visible && root.height > 0);
    }

    screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    visible: root.holding
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
        right: true
        bottom: true
        top: true
    }
    implicitWidth: 360 + 2 * root.shadowRoom
    mask: Region {
        item: list
    }

    Connections {
        target: Notifications
        function onPopupListChanged() {
            if (Notifications.popupList.length > 0) {
                release.stop();
                root.holding = true;
            } else {
                release.restart();
            }
        }
    }

    Timer {
        id: release
        interval: ExLooks.motion.slow
        onTriggered: root.holding = false
    }

    ListView {
        id: list

        x: root.shadowRoom
        width: 360
        height: list.contentHeight
        // The height the list is placed by, kept when the last card goes: it
        // leaves where it stood rather than sinking with the list as it slides.
        property real restHeight: 0
        onContentHeightChanged: {
            if (list.contentHeight > 0)
                list.restHeight = list.contentHeight;
        }
        // Its end against the dock, moving as the stack grows and shrinks. A
        // card going from the far end closes up inside the list over the same
        // time the list moves back, so the cards left stand still.
        y: root.dockAtTop ? root.shadowRoom : root.height - root.shadowRoom - list.restHeight
        Behavior on y {
            enabled: !root.dockAtTop && root.sized
            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
        spacing: ExLooks.spacing.s
        interactive: false
        // A card on its way out stays drawn however small the list has got.
        // The list is only as tall as its cards, and with the last of them
        // going it drew nothing outside its height for a frame or two.
        cacheBuffer: 100000
        // Newest nearest the dock.
        model: ScriptModel {
            values: root.dockAtTop ? [...Notifications.popupList].reverse() : Notifications.popupList
            objectProp: "notificationId"
        }

        delegate: NotificationCard {
            required property var modelData
            notif: modelData
        }

        add: Transition {
            NumberAnimation { property: "x"; from: 380; to: 0; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.enter }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ExLooks.motion.normal }
        }
        remove: Transition {
            NumberAnimation { property: "x"; to: 380; duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.exit }
            NumberAnimation { property: "opacity"; to: 0; duration: ExLooks.motion.fast }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
    }
}
