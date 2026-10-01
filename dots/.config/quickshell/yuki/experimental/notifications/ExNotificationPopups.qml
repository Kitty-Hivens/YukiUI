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
PanelWindow {
    id: root

    readonly property bool dockAtTop: Config.options.experimental.dock.edge === "top"
    readonly property real shadowRoom: 24
    // Held a moment after the last one goes, so it can leave the way it came.
    property bool holding: false

    screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    visible: Notifications.popupList.length > 0 || root.holding
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
        right: true
        bottom: !root.dockAtTop
        top: root.dockAtTop
    }
    implicitWidth: 360 + 2 * root.shadowRoom
    implicitHeight: Math.max(1, list.contentHeight + 2 * root.shadowRoom)
    mask: Region {
        item: list
    }

    Connections {
        target: Notifications
        function onPopupListChanged() {
            if (Notifications.popupList.length === 0) {
                root.holding = true;
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
        y: root.shadowRoom
        width: 360
        height: contentHeight
        spacing: ExLooks.spacing.s
        interactive: false
        // Newest nearest the dock.
        verticalLayoutDirection: root.dockAtTop ? ListView.TopToBottom : ListView.BottomToTop
        model: ScriptModel {
            values: [...Notifications.popupList].reverse()
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
