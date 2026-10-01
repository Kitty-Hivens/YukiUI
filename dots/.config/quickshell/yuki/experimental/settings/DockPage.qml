pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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
    readonly property string shellPath: Quickshell.shellPath("shell.qml")

    /**
     * The tray's icons, asked of the running shell. This window must not watch
     * the tray itself: a second watcher could take the role over from the
     * shell, and the icons would go with it.
     */
    property var trayItems: []
    property bool trayAnswered: false

    function readTray() {
        trayReader.running = true;
    }

    function setTrayShown(id: string, shown: bool) {
        // Moved at once, read back to follow what the shell did.
        root.trayItems = root.trayItems.map(item => item.id === id ? Object.assign({}, item, { shown: shown }) : item);
        Quickshell.execDetached(["qs", "-p", root.shellPath, "ipc", "call", "dock", "setTrayShown", id, String(shown)]);
        trayReadSoon.restart();
    }

    Component.onCompleted: root.readTray()

    Process {
        id: trayReader
        command: ["qs", "-p", root.shellPath, "ipc", "call", "dock", "trayItems"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.trayItems = JSON.parse(text);
                    root.trayAnswered = true;
                } catch (error) {
                    root.trayAnswered = false;
                }
            }
        }
    }
    Timer {
        id: trayReadSoon
        interval: 400
        onTriggered: root.readTray()
    }
    // Icons come and go with their programs.
    Timer {
        running: root.Window.window?.active ?? false
        repeat: true
        interval: 5000
        onTriggered: root.readTray()
    }

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

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("System tray")

        ExText {
            Layout.fillWidth: true
            Layout.bottomMargin: ExLooks.spacing.xs
            text: !root.trayAnswered ? Translation.tr("The shell is not answering, so the tray cannot be listed now")
                : root.trayItems.length === 0 ? Translation.tr("No program has an icon in the tray now")
                : Translation.tr("Shown in the dock, or kept under the arrow beside it")
            wrapMode: Text.Wrap
            dim: true
        }

        Repeater {
            model: root.trayItems

            SettingsCard {
                id: trayCard

                required property var modelData

                Layout.fillWidth: true
                glyph: "widgets"
                iconSource: trayCard.modelData.icon.length > 0 ? Quickshell.iconPath(trayCard.modelData.icon, true) : ""
                text: trayCard.modelData.title
                description: trayCard.modelData.title !== trayCard.modelData.id ? trayCard.modelData.id : ""

                ExSwitch {
                    checked: trayCard.modelData.shown
                    onToggled: root.setTrayShown(trayCard.modelData.id, checked)
                }
            }
        }
    }
}
