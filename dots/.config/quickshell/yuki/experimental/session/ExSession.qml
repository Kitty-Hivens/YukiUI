import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs.core
import qs.core.functions
import qs.core.services
import qs.experimental
import qs.experimental.looks
import qs.experimental.motion

// Lock, sleep, log out, restart and shut down, over a dimmed screen on the
// monitor in focus. The arrows move between them, Enter picks one, Escape or a
// click outside closes it.
Scope {
    id: root

    readonly property var actions: [
        { glyph: "lock", text: Translation.tr("Lock"), run: () => Session.lock() },
        { glyph: "bedtime", text: Translation.tr("Sleep"), run: () => Session.suspend() },
        { glyph: "logout", text: Translation.tr("Logout"), run: () => Session.logout() },
        { glyph: "restart_alt", text: Translation.tr("Reboot"), run: () => Session.reboot() },
        { glyph: "power_settings_new", text: Translation.tr("Shut down"), run: () => Session.poweroff() },
    ]

    ExPresence {
        id: presence
        wanted: ExStates.sessionOpen
    }

    Loader {
        active: presence.present

        sourceComponent: PanelWindow {
            id: window

            screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Closed over a fullscreen game, nothing takes the keyboard back
            // by itself and the game reads its dead input as a freeze.
            Component.onCompleted: FocusReturn.remember("exSession")
            Component.onDestruction: FocusReturn.restore("exSession")

            Rectangle {
                anchors.fill: parent
                color: ExLooks.colors.scrimStrong
                opacity: presence.progress
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ExStates.sessionOpen = false
            }

            RowLayout {
                id: row

                property int current: 0

                anchors.centerIn: parent
                opacity: presence.progress
                scale: 0.9 + 0.1 * presence.progress
                spacing: ExLooks.spacing.xl
                focus: true
                Component.onCompleted: row.forceActiveFocus()

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        ExStates.sessionOpen = false;
                    } else if (event.key === Qt.Key_Left) {
                        row.current = (row.current + root.actions.length - 1) % root.actions.length;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                        row.current = (row.current + 1) % root.actions.length;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        const action = root.actions[row.current];
                        ExStates.sessionOpen = false;
                        action.run();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Repeater {
                    model: root.actions

                    ColumnLayout {
                        id: slot

                        required property var modelData
                        required property int index

                        spacing: ExLooks.spacing.s

                        AbstractButton {
                            id: button

                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 88
                            implicitHeight: 88
                            hoverEnabled: true
                            onHoveredChanged: {
                                if (button.hovered)
                                    row.current = slot.index;
                            }
                            onClicked: {
                                ExStates.sessionOpen = false;
                                slot.modelData.run();
                            }

                            background: ExSurface {
                                radius: width / 2
                                elevation: row.current === slot.index ? 2 : 1
                                color: row.current === slot.index ? ExLooks.colors.accent : ExLooks.colors.surface

                                ExStateLayer {
                                    ink: row.current === slot.index ? ExLooks.colors.accentInk : ExLooks.colors.text
                                    hovered: button.hovered
                                    pressed: button.down
                                }
                            }

                            contentItem: Item {
                                ExGlyph {
                                    anchors.centerIn: parent
                                    text: slot.modelData.glyph
                                    size: 32
                                    color: row.current === slot.index ? ExLooks.colors.accentInk : ExLooks.colors.text
                                }
                            }
                        }
                        ExText {
                            Layout.alignment: Qt.AlignHCenter
                            text: slot.modelData.text
                            role: "label"
                            color: ExLooks.colors.scrimInk
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "session"
        function toggle(): void {
            ExStates.sessionOpen = !ExStates.sessionOpen;
        }
        function open(): void {
            ExStates.sessionOpen = true;
        }
        function close(): void {
            ExStates.sessionOpen = false;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles the session menu"
        onPressed: ExStates.sessionOpen = !ExStates.sessionOpen
    }
    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens the session menu"
        onPressed: ExStates.sessionOpen = true
    }
    GlobalShortcut {
        name: "sessionClose"
        description: "Closes the session menu"
        onPressed: ExStates.sessionOpen = false
    }
}
