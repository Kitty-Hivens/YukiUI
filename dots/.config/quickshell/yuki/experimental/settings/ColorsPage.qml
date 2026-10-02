import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.looks

// Light or dark, for the shell and the applications at once, and the accent
// they share.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    function setMode(dark: bool) {
        if (dark !== ExLooks.dark)
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"]);
    }

    spacing: ExLooks.spacing.s

    // The two modes as small pictures of a window, the way Windows offers them.
    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.m

        Repeater {
            model: [
                { dark: false, name: Translation.tr("Light"), paper: "#eef0f4", card: "#ffffff", ink: "#15161a" },
                { dark: true, name: Translation.tr("Dark"), paper: "#1b1c21", card: "#26272d", ink: "#e9eaf0" }
            ]

            AbstractButton {
                id: mode

                ExPrimaryOnly {
                    z: 1
                }

                required property var modelData
                readonly property bool current: mode.modelData.dark === ExLooks.dark

                Layout.fillWidth: true
                implicitHeight: 190
                hoverEnabled: true
                onClicked: root.setMode(mode.modelData.dark)

                background: Rectangle {
                    radius: ExLooks.radius.tile
                    color: ExLooks.colors.surface
                    border.width: mode.current ? 2 : 1
                    border.color: mode.current ? ExLooks.colors.accent : ExLooks.colors.hairline

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: mode.hovered
                        pressed: mode.down
                    }
                }
                contentItem: ColumnLayout {
                    spacing: ExLooks.spacing.m

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: ExLooks.spacing.m
                        Layout.bottomMargin: 0
                        radius: ExLooks.radius.control
                        color: mode.modelData.paper

                        Rectangle {
                            x: 16
                            y: 16
                            width: parent.width * 0.6
                            height: parent.height - 32
                            radius: 8
                            color: mode.modelData.card

                            Column {
                                x: 12
                                y: 12
                                spacing: 6

                                Rectangle {
                                    width: 60
                                    height: 8
                                    radius: 4
                                    color: mode.modelData.ink
                                    opacity: 0.8
                                }
                                Rectangle {
                                    width: 90
                                    height: 6
                                    radius: 3
                                    color: mode.modelData.ink
                                    opacity: 0.35
                                }
                                Rectangle {
                                    width: 40
                                    height: 14
                                    radius: 7
                                    color: mode.modelData.dark ? "#6179f2" : "#4f6bed"
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.leftMargin: ExLooks.spacing.m
                        Layout.bottomMargin: ExLooks.spacing.m
                        spacing: ExLooks.spacing.s

                        ExGlyph {
                            text: mode.current ? "radio_button_checked" : "radio_button_unchecked"
                            size: 18
                            color: mode.current ? ExLooks.colors.accent : ExLooks.colors.textDim
                        }
                        ExText {
                            text: mode.modelData.name
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "colors"
            text: Translation.tr("Accent color")
            description: Translation.tr("Fixed for this environment, and handed to the applications too")

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: ExLooks.colors.accent
                border.width: 2
                border.color: ExLooks.colors.surface
            }
        }
    }
}
