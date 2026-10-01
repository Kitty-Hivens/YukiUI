import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.looks

// Where the dock stands and how, what it holds, and how it behaves, in the
// order Windows lays out its taskbar settings.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var dock: Config.options.experimental.dock

    spacing: 4

    // The edge is changed by the running shell, which carries the dock there
    // rather than letting it jump.
    SettingsCard {
        Layout.fillWidth: true
        glyph: "dock_to_bottom"
        text: Translation.tr("Edge")
        description: Translation.tr("Which side of the screen the dock stands on")

        SettingsChoice {
            value: root.dock.edge
            options: [
                { value: "bottom", text: Translation.tr("Bottom") },
                { value: "left", text: Translation.tr("Left") },
                { value: "top", text: Translation.tr("Top") },
                { value: "right", text: Translation.tr("Right") }
            ]
            onPicked: edge => Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call", "dock", "move", edge])
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        glyph: "splitscreen_bottom"
        text: Translation.tr("Style")
        description: Translation.tr("Against the edge, standing off it, or only as long as what it holds")

        SettingsChoice {
            value: root.dock.style
            options: [
                { value: "attached", text: Translation.tr("Attached") },
                { value: "floating", text: Translation.tr("Floating") },
                { value: "island", text: Translation.tr("Island") }
            ]
            onPicked: style => Config.options.experimental.dock.style = style
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        glyph: "format_align_center"
        text: Translation.tr("Alignment")
        description: Translation.tr("Where the applications gather along the dock")

        SettingsChoice {
            value: root.dock.alignment
            options: [
                { value: "start", text: Translation.tr("At the start") },
                { value: "center", text: Translation.tr("Center") }
            ]
            onPicked: alignment => Config.options.experimental.dock.alignment = alignment
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Dock items")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "apps"
            text: Translation.tr("Launcher button")
            description: Translation.tr("Super opens the launcher either way")

            ExSwitch {
                checked: root.dock.launcherButton
                onToggled: Config.options.experimental.dock.launcherButton = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "desktop_windows"
            text: Translation.tr("Show the desktop from the far corner")
            description: Translation.tr("A sliver at the end of the dock that minimises every window, and brings them back")

            ExSwitch {
                checked: root.dock.showDesktop
                onToggled: Config.options.experimental.dock.showDesktop = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "counter_1"
            text: Translation.tr("Badges on applications")
            description: Translation.tr("Unread counts and calls for attention on their buttons")

            ExSwitch {
                checked: root.dock.badges
                onToggled: Config.options.experimental.dock.badges = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Clock")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "schedule"
            text: Translation.tr("Show seconds")

            ExSwitch {
                checked: root.dock.clockSeconds
                onToggled: Config.options.experimental.dock.clockSeconds = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "calendar_today"
            text: Translation.tr("Show the date")
            description: Translation.tr("Under the time, on a dock along the top or the bottom")

            ExSwitch {
                checked: root.dock.clockDate
                onToggled: Config.options.experimental.dock.clockDate = checked
            }
        }
    }
}
