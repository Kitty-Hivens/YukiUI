import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.blueberry.looks

// Whether notifications pop up, for how long, and how many are kept afterwards.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    spacing: 4

    SettingsCard {
        Layout.fillWidth: true
        glyph: root.shell?.doNotDisturb ? "notifications_off" : "notifications"
        text: Translation.tr("Do not disturb")
        description: root.shell?.reachable ?? true ? Translation.tr("Notifications are kept without popping up")
            : Translation.tr("The shell is not answering, so this cannot be changed now")

        // The shell's notification server, asked across: a window with one of
        // its own would take the bus over when the shell restarts.
        ExSwitch {
            checked: root.shell?.doNotDisturb ?? false
            onToggled: root.shell.setDoNotDisturb(checked)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        glyph: "timer"
        text: Translation.tr("Shown for")
        description: Translation.tr("Unless the application asks for another time")

        SettingsNumber {
            from: 1
            to: 60
            unit: Translation.tr("s")
            value: Math.round(Config.options.notifications.timeout / 1000)
            onEdited: value => Config.options.notifications.timeout = value * 1000
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        glyph: "inventory_2"
        text: Translation.tr("Keep")
        description: Translation.tr("The oldest go once there are more")

        SettingsNumber {
            from: 10
            to: 1000
            stepSize: 10
            value: Config.options.notifications.keep
            onEdited: value => Config.options.notifications.keep = value
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        glyph: "clear_all"
        text: Translation.tr("Kept now")
        description: Translation.tr("%1 notifications").arg(root.shell?.notificationCount ?? 0)

        ExButton {
            kind: "control"
            text: Translation.tr("Clear all")
            enabled: (root.shell?.notificationCount ?? 0) > 0
            onClicked: root.shell.clearNotifications()
        }
    }
}
