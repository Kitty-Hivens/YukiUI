pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks

// The snipping tool's toolbar, as Windows lays it out: a picture or a video,
// what to take, what to do with a picture, the colour picker, and closing.
ColumnLayout {
    id: root

    /** The tool, whose state the toolbar sets. */
    required property var snip

    spacing: ExLooks.spacing.s

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

            ExToolButton {
                glyph: "photo_camera"
                toggled: root.snip.media === "image"
                onClicked: root.snip.media = "image"
            }
            ExToolButton {
                glyph: "videocam"
                toggled: root.snip.media === "video"
                onClicked: root.snip.media = "video"
            }

            Rule {}

            ExToolButton {
                glyph: "select"
                toggled: root.snip.area === "rect"
                onClicked: root.snip.area = "rect"
            }
            ExToolButton {
                glyph: "select_window"
                toggled: root.snip.area === "window"
                onClicked: root.snip.area = "window"
            }
            ExToolButton {
                glyph: "fit_screen"
                toggled: root.snip.area === "screen"
                onClicked: root.snip.area = "screen"
            }

            Rule {}

            // A picture: marked up before it is kept, or read for its text.
            ExToolButton {
                visible: root.snip.media === "image"
                glyph: "draw"
                toggled: root.snip.markup
                onClicked: {
                    root.snip.markup = !root.snip.markup;
                    if (root.snip.markup)
                        root.snip.textOnly = false;
                }
            }
            ExToolButton {
                visible: root.snip.media === "image"
                glyph: "document_scanner"
                toggled: root.snip.textOnly
                onClicked: {
                    root.snip.textOnly = !root.snip.textOnly;
                    if (root.snip.textOnly)
                        root.snip.markup = false;
                }
            }
            ExToolButton {
                visible: root.snip.media === "image"
                glyph: "colorize"
                onClicked: root.snip.pickColour()
            }
            // A video: with the sound that is playing, or without.
            ExToolButton {
                visible: root.snip.media === "video"
                glyph: root.snip.sound ? "volume_up" : "volume_off"
                toggled: root.snip.sound
                onClicked: root.snip.sound = !root.snip.sound
            }

            Rule {}

            ExToolButton {
                glyph: "close"
                onClicked: root.snip.close()
            }
        }
    }
}
