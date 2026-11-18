import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// Where the dock stands and how it is drawn, with the desktop in miniature
// beside the choices: the real dock moves as well, but it is at the edge of
// the screen and the eyes are here.
WelcomeStep {
    id: root

    readonly property var dock: Config.options.blueberry.dock

    title: Translation.tr("The dock")
    subtitle: Translation.tr("It holds the applications, the open windows, the clock and the tray. Put it where your hand expects it.")

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.settings.groupGap

        WelcomeDesktop {
            Layout.preferredWidth: Math.round(Math.min(480, Math.max(300, root.width * 0.45)))
            Layout.preferredHeight: Math.round(width * 9 / 16)
            Layout.alignment: Qt.AlignTop
            backdrop: ExLooks.settings.pane
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: ExLooks.settings.labelGap

            ExText {
                Layout.leftMargin: ExLooks.settings.rowPadding
                text: Translation.tr("Edge")
                font.pixelSize: ExLooks.settings.small
                font.weight: ExLooks.font.weightTitle
                dim: true
            }
            // The four edges as they lie: the sides beside each other, the
            // top over the bottom.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: [
                        { value: "top", text: Translation.tr("Top") },
                        { value: "left", text: Translation.tr("Left") },
                        { value: "bottom", text: Translation.tr("Bottom") },
                        { value: "right", text: Translation.tr("Right") }
                    ]

                    ExButton {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        kind: modelData.value === root.dock.edge ? "tonal" : "control"
                        text: modelData.text
                        // The edge is changed by the running shell, which
                        // carries the dock there rather than letting it jump.
                        onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call", "dock", "move", modelData.value])
                    }
                }
            }
            SettingsSection {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s

                SettingsCard {
                    Layout.fillWidth: true
                    text: Translation.tr("Hide automatically")
                    description: Translation.tr("Comes out when the pointer reaches the edge")

                    ExSwitch {
                        checked: root.dock.autoHide
                        onToggled: Config.options.blueberry.dock.autoHide = checked
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Style")

        RowLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.s

            Repeater {
                model: [
                    { value: "attached", name: Translation.tr("Attached"), about: Translation.tr("Runs the whole edge") },
                    { value: "floating", name: Translation.tr("Floating"), about: Translation.tr("Stands off the edge") },
                    { value: "island", name: Translation.tr("Island"), about: Translation.tr("Only as long as it needs") }
                ]

                StyleChoice {}
            }
        }
    }

    // A style as a strip of screen with the dock drawn on it, its name under.
    component StyleChoice: AbstractButton {
        id: choice

        ExPrimaryOnly {
            z: 1
        }

        required property var modelData
        readonly property bool chosen: choice.modelData.value === root.dock.style

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: choice.contentItem.implicitHeight
        hoverEnabled: true
        onClicked: Config.options.blueberry.dock.style = choice.modelData.value

        ExFocusRing {
            cornerRadius: ExLooks.radius.control
        }

        background: Rectangle {
            radius: ExLooks.radius.control
            color: choice.chosen ? ExLooks.colors.tonal : ExLooks.settings.sunken
            border.width: choice.chosen ? 2 : 0
            border.color: ExLooks.colors.accent

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: choice.hovered && !choice.chosen
                pressed: choice.down
            }
        }
        contentItem: ColumnLayout {
            spacing: 2

            // The bottom of a screen, and the dock along it, as tall as the
            // card's width gives it, so a wide window does not draw strips.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Math.min(110, Math.max(50, choice.width * 0.3)))
                Layout.margins: ExLooks.spacing.m
                Layout.bottomMargin: ExLooks.spacing.xs

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: ExLooks.settings.plate
                    border.width: 1
                    border.color: ExLooks.colors.hairline
                }
                Rectangle {
                    readonly property bool attached: choice.modelData.value === "attached"
                    readonly property bool island: choice.modelData.value === "island"

                    x: attached ? 1 : island ? parent.width * 0.3 : 5
                    width: attached ? parent.width - 2 : island ? parent.width * 0.4 : parent.width - 10
                    height: 12
                    y: parent.height - height - (attached ? 1 : 5)
                    radius: attached ? 0 : 6
                    bottomLeftRadius: attached ? 5 : 6
                    bottomRightRadius: attached ? 5 : 6
                    color: choice.chosen ? ExLooks.colors.accent : ExLooks.colors.textDim
                    opacity: choice.chosen ? 1 : 0.55
                }
            }
            ExText {
                Layout.leftMargin: ExLooks.spacing.m
                text: choice.modelData.name
                font.pixelSize: ExLooks.settings.body
                font.weight: ExLooks.font.weightLabel
                color: choice.chosen ? ExLooks.colors.tonalInk : ExLooks.colors.text
            }
            ExText {
                Layout.leftMargin: ExLooks.spacing.m
                Layout.bottomMargin: ExLooks.spacing.m
                text: choice.modelData.about
                font.pixelSize: ExLooks.settings.small
                color: choice.chosen ? ExLooks.colors.tonalInk : ExLooks.colors.textDim
            }
        }
    }
}
