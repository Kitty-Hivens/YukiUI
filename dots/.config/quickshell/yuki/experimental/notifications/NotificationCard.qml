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
ExSurface {
    id: root

    required property var notif
    /** Shown in the notification center rather than as it arrives. */
    property bool inCenter: false
    /** The time "ago" counts from. The center moves it on while it is open. */
    property real now: Date.now()

    // What the notification says, kept from the last moment it existed. A
    // dismissed one is destroyed at once, while its toast is still sliding
    // out, and every line reading it directly threw for the rest of the slide.
    property var shown: ({
            notificationId: -1,
            actions: [],
            appIcon: "",
            appName: "",
            body: "",
            image: "",
            summary: "",
            time: 0,
            fromServer: false
        })
    Binding {
        target: root
        property: "shown"
        when: !!root.notif
        restoreMode: Binding.RestoreNone
        value: ({
                notificationId: root.notif?.notificationId ?? -1,
                actions: root.notif?.actions ?? [],
                appIcon: root.notif?.appIcon ?? "",
                appName: root.notif?.appName ?? "",
                body: root.notif?.body ?? "",
                image: root.notif?.image ?? "",
                summary: root.notif?.summary ?? "",
                time: root.notif?.time ?? 0,
                fromServer: !!root.notif?.notification
            })
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
    radius: ExLooks.radius.tile
    elevation: root.inCenter ? 0 : 1
    color: root.inCenter ? ExLooks.colors.surfaceSunken : ExLooks.colors.surface

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
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
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ExText {
                    Layout.fillWidth: true
                    text: root.shown.summary
                    font.weight: 600
                }
                ExText {
                    Layout.fillWidth: true
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
