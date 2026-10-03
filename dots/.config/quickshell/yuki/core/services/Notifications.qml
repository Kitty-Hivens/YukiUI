pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: root.localOnly(notification?.appIcon ?? "")
        property string appName: notification?.appName ?? ""
        property string body: root.withoutRemoteImages(notification?.body ?? "")
        property string image: root.localOnly(notification?.image ?? "")
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        /**
         * The timer belongs to the popup, not to the notification.
         *
         * It only ever destroyed itself when it fired, so one stopped early --
         * by a pointer resting on the popup, or by the popup being dismissed --
         * was left running or left behind. Whichever way the popup goes away,
         * it goes with it.
         */
        function clearTimer() {
            if (!wrapper.timer)
                return;
            wrapper.timer.stop();
            wrapper.timer.destroy();
            wrapper.timer = null;
        }

        /** Everything this notification owns goes when it does. */
        function dispose() {
            wrapper.clearTimer();
            wrapper.destroy();
        }

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    /**
     * A picture or icon a notification names, kept only when it is on this
     * machine: a path, a file url, an image the server was handed as data, or
     * an icon name. Anything else would have the shell fetch it from wherever
     * it points the moment the notification is drawn.
     */
    function localOnly(source: string): string {
        if (source.length === 0 || source.startsWith("/") || source.startsWith("file://") || source.startsWith("image://"))
            return source;
        return source.includes("://") ? "" : source;
    }

    /**
     * The body without pictures from elsewhere. A body is very often written
     * by someone other than the program sending it, a chat message or a mail
     * subject, passed on as it came, and a picture in it pointing at a server
     * told that server the message had been shown, and to whom, as a tracking
     * pixel in a mail does. Pictures on this machine stay.
     */
    function withoutRemoteImages(body: string): string {
        if (!/<img/i.test(body))
            return body;
        return body.replace(/<img\b[^>]*>/gi, tag => {
            const found = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(tag);
            const source = found ? (found[1] ?? found[2] ?? found[3] ?? "") : "";
            return source.startsWith("/") || source.startsWith("file://") ? tag : "";
        });
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const notifObject = root.list.find((notif) => notif.notificationId === notificationId);
            // Gone already, dismissed by hand before this came round. There is
            // nothing left to time out, and reaching into it anyway is what
            // used to throw here -- taking the line that tidied this timer up
            // with it.
            if (!notifObject) {
                destroy();
                return;
            }
            // Both of these clear the timer, so it is not destroyed twice.
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    /**
     * Whether a panel listing notifications is on screen.
     *
     * This used to ask one environment's sidebar for itself, by name, from code
     * that every environment shares -- and after the flag moved to its owner the
     * question answered undefined, so popups arrived over the open list and the
     * unread count climbed while it was being read. What matters here is that
     * someone is looking at the list, not which surface shows it, so whichever
     * desktop is up says so.
     */
    property bool viewerOpen: false
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        // Not offered: pictures in a body are only kept when they are local,
        // see withoutRemoteImages.
        bodyImagesSupported: false
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = [...root.list, newNotifObject];
            root.trimToKeepLimit();

            // A critical one gets through do not disturb, as it does in GNOME,
            // and is not timed out unless the sender asked for a timeout: the
            // specification wants it to stay until someone has seen it. A low
            // battery is the case that matters.
            const critical = notification.urgency === NotificationUrgency.Critical;
            if (!root.viewerOpen && (!root.silent || critical)) {
                newNotifObject.popup = true;
                const expires = notification.expireTimeout > 0 || (notification.expireTimeout < 0 && !critical);
                if (expires) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
            }
            // Arriving in silence is still arriving. Only a list someone is
            // looking at has nothing unread in it.
            if (!root.viewerOpen)
                root.unread++;
            root.notify(newNotifObject);
            // console.log(notifToString(newNotifObject));
            notifFileView.setText(stringifyList(root.list));
        }
    }

    /**
     * Drops the oldest once there are more than the configured number.
     *
     * The list had no ceiling, and every new notification rewrites the whole of
     * it to disk, so a machine nobody clears notifications on wrote a steadily
     * larger file on every one that arrived.
     */
    function trimToKeepLimit() {
        const keep = Config?.options.notifications.keep ?? 200;
        if (keep <= 0 || root.list.length <= keep)
            return;
        const dropped = root.list.slice(0, root.list.length - keep);
        root.list = root.list.slice(root.list.length - keep);
        dropped.forEach((notif) => notif?.dispose());
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            const notifObject = root.list[index];
            root.list.splice(index, 1);
            notifFileView.setText(stringifyList(root.list));
            triggerListChange()
            // Taken off the list and then left in memory, every notification the
            // shell had ever shown was still there at the end of the day.
            notifObject.dispose();
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardAllNotifications() {
        const previous = root.list.slice(0);
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        previous.forEach((notif) => notif?.dispose());
        root.discardAll();
    }

    function cancelTimeout(id) {
        // A notification that never expires has no timer to stop, and resting a
        // pointer on one was reaching into it regardless.
        root.list.find((notif) => notif.notificationId === id)?.timer?.stop();
    }

    function timeoutNotification(id) {
        const notifObject = root.list.find((notif) => notif.notificationId === id);
        if (notifObject) {
            notifObject.popup = false;
            notifObject.clearTimer();
        }
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            action.invoke()
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    /**
     * The way in from another process, a settings window say, which must not
     * hold a notification server of its own: it would take the bus over from
     * the shell the moment the shell restarted.
     */
    IpcHandler {
        target: "notifications"

        function silent(): string {
            return root.silent ? "on" : "off";
        }
        function setSilent(on: bool): void {
            root.silent = on;
        }
        function count(): int {
            return root.list.length;
        }
        function clear(): void {
            root.discardAllNotifications();
        }
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            let saved;
            try {
                saved = JSON.parse(notifFileView.text());
            } catch (error) {
                // A file that cannot be read is not a reason to stop halfway
                // through loading, which is what an exception here did: the
                // list kept whatever it had and the rest of this never ran.
                console.error("[Notifications] stored notifications could not be read, starting empty:", error);
                saved = [];
            }
            if (!Array.isArray(saved))
                saved = [];
            root.list = saved.map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    // Read back through the same filter as a live one, since a
                    // file written before it can hold what it now keeps out.
                    "appIcon": root.localOnly(notif.appIcon ?? ""),
                    "appName": notif.appName,
                    "body": root.withoutRemoteImages(notif.body ?? ""),
                    "image": root.localOnly(notif.image ?? ""),
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            // Applies the ceiling to a file written before there was one.
            root.trimToKeepLimit()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
