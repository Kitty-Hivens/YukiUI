pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services
import qs.blueberry.looks

// Where the dock stands and how, what it holds, and how it behaves, in the
// order Windows lays out its taskbar settings.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var dock: Config.options.blueberry.dock
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

    spacing: ExLooks.settings.groupGap

    SettingsSection {
        Layout.fillWidth: true

        // The edge is changed by the running shell, which carries the dock there
        // rather than letting it jump.
        SettingsCard {
            Layout.fillWidth: true
            glyph: "dock_to_bottom"
            text: Translation.tr("Edge")

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

            SettingsChoice {
                value: root.dock.style
                options: [
                    { value: "attached", text: Translation.tr("Attached") },
                    { value: "floating", text: Translation.tr("Floating") },
                    { value: "island", text: Translation.tr("Island") }
                ]
                onPicked: style => Config.options.blueberry.dock.style = style
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "format_align_center"
            text: Translation.tr("Alignment")

            SettingsChoice {
                value: root.dock.alignment
                options: [
                    { value: "start", text: Translation.tr("At the start") },
                    { value: "center", text: Translation.tr("Center") }
                ]
                onPicked: alignment => Config.options.blueberry.dock.alignment = alignment
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Look")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "opacity"
            text: Translation.tr("Opacity")

            Row {
                spacing: ExLooks.spacing.m

                ExText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: `${Math.round(opacitySlider.value)}%`
                    dim: true
                }
                ExSlider {
                    id: opacitySlider

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 200
                    from: 30
                    to: 100
                    stepSize: 1
                    value: root.dock.opacity
                    // Shown on the dock as the knob moves, so it can be judged
                    // there, but written at most every 80 ms: the dock is in
                    // another process and hears of it through the config file.
                    // Written once more as the knob is let go, for the last step.
                    onMoved: {
                        if (!opacityWrite.running)
                            opacityWrite.start();
                    }
                    onPressedChanged: {
                        if (!pressed) {
                            opacityWrite.stop();
                            Config.options.blueberry.dock.opacity = Math.round(value);
                        }
                    }

                    Timer {
                        id: opacityWrite
                        interval: 80
                        onTriggered: Config.options.blueberry.dock.opacity = Math.round(opacitySlider.value)
                    }
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "blur_on"
            text: Translation.tr("Blur behind the dock")

            ExSwitch {
                checked: root.dock.blur
                onToggled: Config.options.blueberry.dock.blur = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Behaviour")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "visibility_off"
            text: Translation.tr("Automatically hide the dock")
            description: Translation.tr("Comes out when the pointer reaches the edge")

            ExSwitch {
                checked: root.dock.autoHide
                onToggled: Config.options.blueberry.dock.autoHide = checked
            }
        }

        SettingsCard {
            Layout.fillWidth: true
            glyph: "label"
            text: Translation.tr("Combine buttons and hide labels")
            description: Translation.tr("Not on a dock at the side")

            SettingsChoice {
                value: root.dock.combine
                options: [
                    { value: "always", text: Translation.tr("Always") },
                    { value: "whenFull", text: Translation.tr("When full") },
                    { value: "never", text: Translation.tr("Never") }
                ]
                onPicked: value => Config.options.blueberry.dock.combine = value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "select_window"
            text: Translation.tr("Windows shown")

            SettingsChoice {
                value: root.dock.windowsFrom
                options: [
                    { value: "workspace", text: Translation.tr("This workspace") },
                    { value: "all", text: Translation.tr("All") }
                ]
                onPicked: value => Config.options.blueberry.dock.windowsFrom = value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: Quickshell.screens.length > 1
            glyph: "desktop_windows"
            text: Translation.tr("Show the dock on")
            description: Translation.tr("The main screen is the one furthest left")

            SettingsChoice {
                value: root.dock.screens
                options: [
                    { value: "all", text: Translation.tr("Every screen") },
                    { value: "main", text: Translation.tr("The main screen") }
                ]
                onPicked: value => Config.options.blueberry.dock.screens = value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: Quickshell.screens.length > 1 && root.dock.screens === "all" && root.dock.windowsFrom === "all"
            glyph: "screenshot_monitor"
            text: Translation.tr("Applications on each dock")

            SettingsChoice {
                value: root.dock.appsOn
                options: [
                    { value: "all", text: Translation.tr("All") },
                    { value: "own", text: Translation.tr("Its own screen") }
                ]
                onPicked: value => Config.options.blueberry.dock.appsOn = value
            }
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
                onToggled: Config.options.blueberry.dock.launcherButton = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "desktop_windows"
            text: Translation.tr("Show the desktop from the far corner")

            ExSwitch {
                checked: root.dock.showDesktop
                onToggled: Config.options.blueberry.dock.showDesktop = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "counter_1"
            text: Translation.tr("Badges on applications")
            description: Translation.tr("Unread counts and calls for attention")

            ExSwitch {
                checked: root.dock.badges
                onToggled: Config.options.blueberry.dock.badges = checked
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
                onToggled: Config.options.blueberry.dock.clockSeconds = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "calendar_today"
            text: Translation.tr("Show the date")
            description: Translation.tr("Only on a horizontal dock")

            ExSwitch {
                checked: root.dock.clockDate
                onToggled: Config.options.blueberry.dock.clockDate = checked
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
