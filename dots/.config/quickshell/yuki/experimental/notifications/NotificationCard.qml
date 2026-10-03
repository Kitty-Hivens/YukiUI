import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core.services
import qs.experimental.looks

// One notification: the application, the summary and the body, a picture when
// it brings one, and its actions. A click runs its default action and the cross
// dismisses it. As it arrives, a pointer resting on it holds it on screen. Kept
// in the notification center, it lies flat and says how long ago it came.
//
// Pulled to the right with the mouse it goes, as on GNOME and Windows: in the
// center it is dismissed, as it arrives it is put away into the center, as a
// click does. Short of a third of its width, and not flung, it springs back.
//
// The plate is drawn inside an outer item that the lists move and fade as cards
// come and go. A list's transition writes those properties outright, and the
// swipe, bound to the plate instead, outlives it.
Item {
    id: root

    required property var notif
    /** Shown in the notification center rather than as it arrives. */
    property bool inCenter: false
    /** The time "ago" counts from. The center moves it on while it is open. */
    property real now: Date.now()

    // What the notification says, kept from the last moment it existed. A
    // dismissed one is destroyed at once, while its toast is still sliding
    // out, and every line reading it directly threw for the rest of the slide.
    //
    // Read from the notification as the card is made, and kept up to date by
    // the binding after. Filled in by the binding alone, a card was made empty
    // and grew as its text arrived, after the list had placed it.
    function snapshot(notif): var {
        return {
            notificationId: notif?.notificationId ?? -1,
            actions: notif?.actions ?? [],
            appIcon: notif?.appIcon ?? "",
            appName: notif?.appName ?? "",
            body: notif?.body ?? "",
            image: notif?.image ?? "",
            summary: notif?.summary ?? "",
            time: notif?.time ?? 0,
            fromServer: !!notif?.notification
        };
    }
    property var shown: root.snapshot(root.notif)
    // Held from here on rather than bound, which followed the wrapper into
    // emptiness and the notification into null.
    Component.onCompleted: root.shown = root.snapshot(root.notif)

    // Brought up to date as the notification changes in place, a sender
    // replacing it say, and only while what the server holds is there. The
    // wrapper outlives that by a moment with every field emptied, and a card
    // bound to it left blank on a click, on Clear all, and when the sender
    // closed it. A condition on the binding did not hold it: which of the
    // two moved first was not the binding's to choose.
    function follow() {
        if (root.notif && (root.notif.notification || !root.shown.fromServer))
            root.shown = root.snapshot(root.notif);
    }
    Connections {
        target: root.notif
        function onSummaryChanged() {
            root.follow();
        }
        function onBodyChanged() {
            root.follow();
        }
        function onAppNameChanged() {
            root.follow();
        }
        function onAppIconChanged() {
            root.follow();
        }
        function onImageChanged() {
            root.follow();
        }
        function onActionsChanged() {
            root.follow();
        }
    }

    readonly property var defaultAction: root.shown.actions.find(action => action.identifier === "default") ?? null
    readonly property var buttons: root.shown.actions.filter(action => action.identifier !== "default")
    // A picture the sender handed over lives in the shell process that took
    // the notification, so one kept from before a restart points at nothing.
    readonly property string picture: root.shown.image.startsWith("image://qsimage/") && !root.shown.fromServer ? "" : root.shown.image
    readonly property string iconSource: root.shown.appIcon.length === 0 ? ""
        : (root.shown.appIcon.startsWith("/") || root.shown.appIcon.includes("://") ? root.shown.appIcon : Quickshell.iconPath(root.shown.appIcon, true))

    /** How long ago, in words, for the notification center. */
    function ago(time: real): string {
        const minutes = Math.floor((root.now - time) / 60000);
        if (minutes < 1)
            return Translation.tr("Now");
        if (minutes < 60)
            return Translation.tr("%1 min ago").arg(minutes);
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return Translation.tr("%1 h ago").arg(hours);
        return Qt.locale().toString(new Date(time), "d MMM");
    }

    width: 360
    implicitHeight: content.implicitHeight + 2 * ExLooks.spacing.m

    /** How far the plate has been pulled to the right. */
    property real swipe: 0
    readonly property real swipeAway: root.width + 40

    /** Sends the card off to the right and dismisses it, or puts it back. */
    function settle(velocity: real) {
        const going = root.swipe > root.width / 3 || velocity > 900;
        swipeBack.stop();
        swipeOut.stop();
        if (going) {
            swipeOut.from = root.swipe;
            swipeOut.start();
        } else {
            swipeBack.from = root.swipe;
            swipeBack.start();
        }
    }

    function dismiss() {
        // The list it is in has nothing left to show of it going.
        if (root.ListView.view?.swiped !== undefined)
            root.ListView.view.swiped = true;
        if (root.inCenter)
            Notifications.discardNotification(root.shown.notificationId);
        else
            Notifications.timeoutNotification(root.shown.notificationId);
    }

    NumberAnimation {
        id: swipeOut
        target: root
        property: "swipe"
        to: root.swipeAway
        duration: ExLooks.motion.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.exit
        onFinished: root.dismiss()
    }
    NumberAnimation {
        id: swipeBack
        target: root
        property: "swipe"
        to: 0
        duration: ExLooks.motion.normal
        easing.type: Easing.OutBack
    }

    ExSurface {
        id: surface

        width: root.width
        height: root.height
        radius: ExLooks.radius.tile
        elevation: root.inCenter ? 0 : 1
        color: root.inCenter ? ExLooks.colors.surfaceSunken : ExLooks.colors.surface
        transform: Translate {
            x: root.swipe
        }
        opacity: 1 - 0.7 * Math.min(1, root.swipe / root.width)

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true

            // Here rather than on the plate: the area takes the press before
            // anything under it, and its own handlers before it. Past the drag
            // threshold the handler takes the press over, and no click follows.
            DragHandler {
                id: swipeDrag

                target: null
                yAxis.enabled: false
                acceptedButtons: Qt.LeftButton
                // Measured on the scene: the area moves with the plate it is
                // pulling, and its own coordinates would follow it.
                onCentroidChanged: {
                    if (swipeDrag.active)
                        root.swipe = Math.max(0, swipeDrag.centroid.scenePosition.x - swipeDrag.centroid.scenePressPosition.x);
                }
                onActiveChanged: {
                    if (swipeDrag.active) {
                        swipeBack.stop();
                        swipeOut.stop();
                    } else {
                        root.settle(swipeDrag.centroid.velocity.x);
                    }
                }
            }

            onContainsMouseChanged: {
                if (root.inCenter)
                    return;
                if (mouse.containsMouse)
                    Notifications.cancelTimeout(root.shown.notificationId);
                else
                    root.notif?.timer?.restart();
            }
            onClicked: {
                if (root.defaultAction)
                    Notifications.attemptInvokeAction(root.shown.notificationId, "default");
                else if (!root.inCenter)
                    Notifications.timeoutNotification(root.shown.notificationId);
            }
        }

        ColumnLayout {
            id: content

            x: ExLooks.spacing.m
            y: ExLooks.spacing.m
            width: parent.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.xs

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.s

                IconImage {
                    visible: root.iconSource.length > 0
                    implicitSize: 16
                    source: root.iconSource
                }
                ExText {
                    Layout.fillWidth: true
                    text: root.inCenter ? `${root.shown.appName}  ·  ${root.ago(root.shown.time)}` : root.shown.appName
                    role: "caption"
                    dim: true
                }
                ExButton {
                    kind: "flat"
                    implicitWidth: 24
                    implicitHeight: 24
                    onClicked: Notifications.discardNotification(root.shown.notificationId)

                    ExGlyph {
                        anchors.centerIn: parent
                        text: "close"
                        size: 16
                        color: ExLooks.colors.textDim
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.m

                Image {
                    visible: root.picture.length > 0
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignTop
                    source: root.picture
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                // A plain column of a width known from the start. Laid out by a
                // layout, the body was given its width only on the layout's next
                // pass, so the card was made a line short and grew a moment
                // later, which the stack of cards as they arrive, laid out from
                // the bottom, took as growing downwards, under the dock.
                Column {
                    readonly property real textWidth: root.width - 2 * ExLooks.spacing.m - (root.picture.length > 0 ? 48 + ExLooks.spacing.m : 0)

                    Layout.fillWidth: true
                    Layout.preferredWidth: textWidth
                    width: textWidth
                    spacing: 2

                    ExText {
                        width: parent.width
                        text: root.shown.summary
                        font.weight: 600
                    }
                    ExText {
                        width: parent.width
                        visible: text.length > 0
                        font.pixelSize: ExLooks.font.label
                        text: root.shown.body
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        dim: true
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.xs
                visible: root.buttons.length > 0
                spacing: ExLooks.spacing.s

                Repeater {
                    model: root.buttons
                    ExButton {
                        required property var modelData
                        Layout.fillWidth: true
                        kind: "control"
                        text: modelData.text
                        onClicked: Notifications.attemptInvokeAction(root.shown.notificationId, modelData.identifier)
                    }
                }
            }
        }
    }
}
