import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.experimental
import qs.experimental.looks
import qs.experimental.notifications

// What the clock opens: the notifications kept so far, newest first, and the
// calendar under them. Opening it counts them as seen, and while it is open new
// ones land here instead of popping up over it.
ExPopup {
    id: root

    readonly property var notifications: [...Notifications.list].reverse()
    // What the cards count "ago" from, moved on while anyone can read it.
    property real now: Date.now()

    Timer {
        running: root.open
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    motion: "panel"
    onDismissRequested: root.open = false
    onOpenChanged: {
        ExStates.notificationViewers += root.open ? 1 : -1;
        if (root.open) {
            // What is popping up is already in the list, and the toasts sit in
            // the same corner, over it.
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }
    Component.onDestruction: {
        if (root.open)
            ExStates.notificationViewers -= 1;
    }

    ColumnLayout {
        width: 380
        spacing: ExLooks.spacing.m

        RowLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.xs

            ExText {
                Layout.fillWidth: true
                text: Translation.tr("Notifications")
                role: "title"
            }
            ExButton {
                kind: Notifications.silent ? "tonal" : "flat"
                glyph: Notifications.silent ? "notifications_off" : "notifications"
                onClicked: Notifications.silent = !Notifications.silent
            }
            ExButton {
                visible: root.notifications.length > 0
                kind: "flat"
                text: Translation.tr("Clear all")
                onClicked: Notifications.discardAllNotifications()
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(cards.implicitHeight, 440)
            visible: root.notifications.length > 0
            clip: true
            contentHeight: cards.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Column {
                id: cards

                width: parent.width
                spacing: ExLooks.spacing.s

                Repeater {
                    model: ScriptModel {
                        values: root.notifications
                        objectProp: "notificationId"
                    }

                    NotificationCard {
                        required property var modelData
                        notif: modelData
                        inCenter: true
                        now: root.now
                        width: cards.width
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.l
            Layout.bottomMargin: ExLooks.spacing.l
            visible: root.notifications.length === 0
            spacing: ExLooks.spacing.s

            ExGlyph {
                Layout.alignment: Qt.AlignHCenter
                text: "notifications_none"
                size: 32
                color: ExLooks.colors.textDim
            }
            // Filling the width is what lets the column around it fill it too:
            // a layout is no wider than the widest of its children allows.
            ExText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("No new notifications")
                dim: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: ExLooks.colors.border
        }

        ExCalendar {
            Layout.fillWidth: true
        }
    }
}
