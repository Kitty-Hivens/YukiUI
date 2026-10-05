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

    /** Clear all was pressed, and the cards are on their way out one after another. */
    property bool clearing: false
    readonly property int cascadeStep: 35
    /** How long the last of the cards cleared takes to be gone. */
    property int clearTime: 0
    /**
     * How long the cards leaving take to be gone, after which the rest close
     * up, the list shrinks and the empty state opens, all at once. A card
     * pulled away by hand is gone already.
     */
    readonly property int goneAfter: root.clearing ? root.clearTime : cards.goneSwiped !== -1 ? 0 : ExLooks.motion.fast
    /**
     * The empty state, shown once the cards have gone rather than over them as
     * they go, and hidden at once as one arrives.
     */
    property bool showEmpty: root.notifications.length === 0
    onNotificationsChanged: {
        // Whether this change took the card that was pulled away. Decided
        // once per change, so a card closed by its cross right after another
        // was pulled away still slides out.
        const swiped = cards.swipedId;
        cards.swipedId = -1;
        cards.goneSwiped = swiped !== -1 && !root.notifications.some(notif => notif.notificationId === swiped) ? swiped : -1;
        if (root.notifications.length > 0) {
            emptyLater.stop();
            root.showEmpty = false;
        } else if (!root.showEmpty) {
            emptyLater.interval = root.goneAfter;
            emptyLater.restart();
        }
    }
    Timer {
        id: emptyLater
        onTriggered: root.showEmpty = true
    }
    // Over once everything has moved, well after the last card has gone.
    Timer {
        id: settled
        interval: root.clearTime + 2 * ExLooks.motion.normal
        onTriggered: root.clearing = false
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
                onClicked: {
                    root.clearTime = Math.min(root.notifications.length - 1, 10) * root.cascadeStep + ExLooks.motion.fast;
                    root.clearing = true;
                    settled.restart();
                    Notifications.discardAllNotifications();
                }
            }
        }

        // The cards and what stands in for them with none kept, with no gap of
        // the column between them: the gap before the empty state opens and
        // closes with it. Given by the column, it came and went at once as
        // the empty state was shown and hidden, and the panel jumped by it.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            // The cards come and go in place: one dismissed slides off to the right
            // and the rest close up after it, one arriving fades in at the top and
            // pushes them down, and clearing them all sends them off one after
            // another. The list, and the panel with it, grows and shrinks to them
            // rather than jumping.
            ListView {
                id: cards

                readonly property real limit: 440
                readonly property real wanted: Math.min(cards.contentHeight, cards.limit)
                property real shownHeight: 0
                Behavior on shownHeight {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                // Shrinking, it waits for the card going to be gone first, as the
                // cards under it do, so the panel and the cards close up together.
                // Growing, it makes room at once.
                onWantedChanged: {
                    if (cards.wanted < cards.shownHeight) {
                        shrinkLater.interval = root.goneAfter;
                        shrinkLater.restart();
                    } else {
                        shrinkLater.stop();
                        cards.shownHeight = cards.wanted;
                    }
                }
                Component.onCompleted: cards.shownHeight = cards.wanted
                Timer {
                    id: shrinkLater
                    onTriggered: cards.shownHeight = cards.wanted
                }

                /** The card pulled away by hand, out of sight already, until the list lets it go. */
                property int swipedId: -1
                /** The card the last change let go of that had been pulled away, or -1. */
                property int goneSwiped: -1

                Layout.fillWidth: true
                Layout.preferredHeight: cards.shownHeight
                clip: true
                spacing: ExLooks.spacing.s
                boundsBehavior: Flickable.StopAtBounds
                // Every card within the limit made whatever the height on show,
                // so the height measured up to the limit is that of the cards,
                // not an estimate. Past it the estimate does, the list being
                // held at the limit there anyway. Every card kept, as many as
                // two hundred stayed made on every screen with the center shut.
                cacheBuffer: cards.limit

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                model: ScriptModel {
                    values: root.notifications
                    objectProp: "notificationId"
                }

                delegate: NotificationCard {
                    required property var modelData
                    notif: modelData
                    inCenter: true
                    now: root.now
                    width: cards.width
                }

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ExLooks.motion.normal }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.enter }
                }
                addDisplaced: Transition {
                    NumberAnimation { property: "y"; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
                // Cleared all at once, each goes a little after the one above it.
                remove: Transition {
                    SequentialAnimation {
                        PauseAnimation { duration: root.clearing ? Math.min(ViewTransition.index, 10) * root.cascadeStep : 0 }
                        ParallelAnimation {
                            NumberAnimation { property: "x"; to: cards.width + 40; duration: ViewTransition.item?.shown.notificationId === cards.goneSwiped ? 0 : ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.exit }
                            NumberAnimation { property: "opacity"; to: 0; duration: ViewTransition.item?.shown.notificationId === cards.goneSwiped ? 0 : ExLooks.motion.fast }
                        }
                    }
                }
                // The rest close up once the cards going have gone.
                removeDisplaced: Transition {
                    SequentialAnimation {
                        PauseAnimation { duration: root.goneAfter }
                        NumberAnimation { property: "y"; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                    }
                }
            }

            // What is shown with nothing kept, opening up where the cards were once
            // the last of them has gone, and closing again as one arrives.
            Item {
                id: empty

                property real shown: root.showEmpty ? 1 : 0
                Behavior on shown {
                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }

                Layout.fillWidth: true
                Layout.preferredHeight: (ExLooks.spacing.m + emptyContent.implicitHeight) * empty.shown
                visible: empty.shown > 0
                opacity: empty.shown
                clip: true

                ColumnLayout {
                    id: emptyContent

                    y: ExLooks.spacing.m
                    width: parent.width
                    spacing: ExLooks.spacing.s

                    ExGlyph {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: ExLooks.spacing.l
                        text: "notifications_none"
                        size: 32
                        color: ExLooks.colors.textDim
                    }
                    ExText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: ExLooks.spacing.l
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("No new notifications")
                        dim: true
                    }
                }
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
