import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import qs
import qs.core.services
import qs.experimental.looks
import qs.experimental.motion

// An application asking to share the screen: a screen or a window to pick, each
// as a live picture, or a part of a screen to draw, and whether to remember the
// choice. The exchange with the portal is the shared service's.
Scope {
    id: root

    ExPresence {
        id: presence
        wanted: GlobalStates.screenSharePickerOpen
    }

    Loader {
        active: presence.present

        sourceComponent: PanelWindow {
            id: window

            property bool showWindows: false

            screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:screenSharePicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function toplevelFor(address: string): var {
                const wanted = address.replace(/^0x/, "");
                return ToplevelManager.toplevels.values.find(toplevel => (toplevel.HyprlandToplevel?.address ?? "") === wanted) ?? null;
            }

            Rectangle {
                anchors.fill: parent
                color: ExLooks.colors.scrim
                opacity: presence.progress
            }
            MouseArea {
                anchors.fill: parent
                onClicked: ScreenShare.cancel()
            }

            ExSurface {
                anchors.centerIn: parent
                opacity: presence.progress
                scale: 0.94 + 0.06 * presence.progress
                width: 760
                height: 540
                radius: ExLooks.radius.panel
                elevation: 2

                // Takes the clicks that land on the card, which would otherwise
                // reach the backdrop and cancel.
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ExLooks.spacing.xl
                    spacing: ExLooks.spacing.l
                    focus: true
                    Component.onCompleted: forceActiveFocus()
                    Keys.onEscapePressed: ScreenShare.cancel()

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ExLooks.spacing.m

                        ExText {
                            Layout.fillWidth: true
                            text: Translation.tr("Share your screen")
                            role: "title"
                        }
                        ExButton {
                            kind: window.showWindows ? "control" : "accent"
                            text: Translation.tr("Screens")
                            onClicked: window.showWindows = false
                        }
                        ExButton {
                            kind: window.showWindows ? "accent" : "control"
                            text: Translation.tr("App windows")
                            onClicked: window.showWindows = true
                        }
                        // Leaves the picker for drawing, and comes back to it
                        // when the drawing is abandoned.
                        ExButton {
                            kind: "control"
                            glyph: "crop"
                            text: Translation.tr("Region")
                            onClicked: ScreenShare.selectRegion()
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: grid.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Grid {
                            id: grid
                            width: parent.width
                            columns: 3
                            spacing: ExLooks.spacing.s

                            Repeater {
                                model: window.showWindows ? ScreenShare.windowEntries : Quickshell.screens

                                AbstractButton {
                                    id: card

                                    ExPrimaryOnly {
                                        z: 1
                                    }

                                    required property var modelData
                                    readonly property var source: window.showWindows ? window.toplevelFor(card.modelData.address) : card.modelData

                                    width: (grid.width - 2 * grid.spacing) / 3
                                    implicitHeight: 172
                                    hoverEnabled: true
                                    onClicked: ScreenShare.submit(window.showWindows ? `window:${card.modelData.id}` : `screen:${card.modelData.name}`)

                                    background: Rectangle {
                                        radius: ExLooks.radius.tile
                                        color: "transparent"
                                        border.width: card.hovered ? 2 : 0
                                        border.color: ExLooks.colors.accent

                                        ExStateLayer {
                                            ink: ExLooks.colors.text
                                            hovered: card.hovered
                                            pressed: card.down
                                        }
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: ExLooks.spacing.xs

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 128
                                            Layout.margins: ExLooks.spacing.xs
                                            radius: ExLooks.radius.control
                                            color: ExLooks.colors.surfaceSunken
                                            clip: true

                                            ScreencopyView {
                                                anchors.centerIn: parent
                                                captureSource: card.source
                                                live: true
                                                constraintSize: Qt.size(parent.width, parent.height)
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: ExLooks.spacing.s
                                            Layout.rightMargin: ExLooks.spacing.s
                                            spacing: ExLooks.spacing.s

                                            IconImage {
                                                visible: window.showWindows
                                                implicitSize: 16
                                                source: window.showWindows ? AppSearch.iconFor(card.modelData.windowClass) : ""
                                            }
                                            ExText {
                                                Layout.fillWidth: true
                                                text: window.showWindows ? card.modelData.title : card.modelData.name
                                                role: "label"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ExText {
                            anchors.centerIn: parent
                            visible: window.showWindows && ScreenShare.windowEntries.length === 0
                            text: Translation.tr("No shareable windows")
                            dim: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ExLooks.spacing.m

                        ExSwitch {
                            checked: ScreenShare.allowToken
                            onToggled: ScreenShare.allowToken = checked
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: Translation.tr("Remember choice")
                        }
                        ExButton {
                            kind: "control"
                            text: Translation.tr("Cancel")
                            onClicked: ScreenShare.cancel()
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "screenShare"

        function open(allowToken: string, fifo: string, windowList: string): void {
            ScreenShare.open(allowToken, fifo, windowList);
        }
        function close(): void {
            ScreenShare.cancel();
        }
    }
}
