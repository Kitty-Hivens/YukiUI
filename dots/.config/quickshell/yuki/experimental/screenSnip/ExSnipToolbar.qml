pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// The snipping tool's toolbar, as Windows lays it out: a picture or a video,
// what to take, what to do with a picture, the colour picker, and closing.
ColumnLayout {
    id: root

    /** The tool, whose state the toolbar sets. */
    required property var snip

    spacing: ExLooks.spacing.s

    component ToolButton: AbstractButton {
        id: tool

        ExPrimaryOnly {
            z: 1
        }

        property string glyph
        property bool toggled: false

        implicitWidth: 40
        implicitHeight: 40
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        opacity: enabled ? 1 : ExLooks.colors.disabledOpacity

        background: Rectangle {
            radius: ExLooks.radius.control
            color: tool.toggled ? ExLooks.colors.tonal : "transparent"

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: tool.hovered && tool.enabled
                pressed: tool.down
            }
        }
        contentItem: Item {
            ExGlyph {
                anchors.centerIn: parent
                text: tool.glyph
                size: 20
                fill: tool.toggled ? 1 : 0
                color: tool.toggled ? ExLooks.colors.tonalInk : ExLooks.colors.text
            }
        }
    }

    component Rule: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 1
        implicitHeight: 24
        color: ExLooks.colors.border
    }

    ExSurface {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: tools.implicitWidth + 2 * ExLooks.spacing.s
        implicitHeight: tools.implicitHeight + 2 * ExLooks.spacing.s
        radius: ExLooks.radius.panel
        elevation: 2

        RowLayout {
            id: tools

            anchors.centerIn: parent
            spacing: ExLooks.spacing.xs

            ToolButton {
                glyph: "photo_camera"
                toggled: root.snip.media === "image"
                onClicked: root.snip.media = "image"
            }
            ToolButton {
                glyph: "videocam"
                toggled: root.snip.media === "video"
                onClicked: root.snip.media = "video"
            }

            Rule {}

            ToolButton {
                glyph: "select"
                toggled: root.snip.area === "rect"
                onClicked: root.snip.area = "rect"
            }
            ToolButton {
                glyph: "select_window"
                toggled: root.snip.area === "window"
                onClicked: root.snip.area = "window"
            }
            ToolButton {
                glyph: "fit_screen"
                toggled: root.snip.area === "screen"
                onClicked: root.snip.area = "screen"
            }

            Rule {}

            // A picture: marked up before it is kept, or read for its text.
            ToolButton {
                visible: root.snip.media === "image"
                glyph: "draw"
                toggled: root.snip.markup
                onClicked: {
                    root.snip.markup = !root.snip.markup;
                    if (root.snip.markup)
                        root.snip.textOnly = false;
                }
            }
            ToolButton {
                visible: root.snip.media === "image"
                glyph: "document_scanner"
                toggled: root.snip.textOnly
                onClicked: {
                    root.snip.textOnly = !root.snip.textOnly;
                    if (root.snip.textOnly)
                        root.snip.markup = false;
                }
            }
            ToolButton {
                visible: root.snip.media === "image"
                glyph: "colorize"
                onClicked: root.snip.pickColour()
            }
            // A video: with the sound that is playing, or without.
            ToolButton {
                visible: root.snip.media === "video"
                glyph: root.snip.sound ? "volume_up" : "volume_off"
                toggled: root.snip.sound
                onClicked: root.snip.sound = !root.snip.sound
            }

            Rule {}

            ToolButton {
                glyph: "close"
                onClicked: root.snip.close()
            }
        }
    }
}
