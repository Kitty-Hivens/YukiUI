import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.blueberry.looks

// A setting with others that belong to it, the way Windows 11 groups them: a
// header like a card's, with its own control and a chevron, and under it the
// rows it opens onto, inside the same frame and parted by rules. The rows are
// SettingsCards with `flat` set.
ColumnLayout {
    id: root

    property string glyph: ""
    property string text: ""
    property string description: ""
    property bool expanded: false
    /** The header's control, at its far end before the chevron. */
    property alias control: controlSlot.data
    default property alias rows: body.data

    spacing: 0

    AbstractButton {
        id: header

        ExPrimaryOnly {
            z: 1
        }

        readonly property real bottomRadius: root.expanded ? 0 : ExLooks.radius.card

        Layout.fillWidth: true
        implicitHeight: Math.max(68, headerRow.implicitHeight + 2 * ExLooks.spacing.m)
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        background: Rectangle {
            color: ExLooks.colors.surface
            border.width: 1
            border.color: ExLooks.colors.hairline
            topLeftRadius: ExLooks.radius.card
            topRightRadius: ExLooks.radius.card
            bottomLeftRadius: header.bottomRadius
            bottomRightRadius: header.bottomRadius

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: header.hovered
                pressed: header.down
                topLeftRadius: ExLooks.radius.card
                topRightRadius: ExLooks.radius.card
                bottomLeftRadius: header.bottomRadius
                bottomRightRadius: header.bottomRadius
            }
        }

        contentItem: Item {
            RowLayout {
                id: headerRow

                anchors.fill: parent
                anchors.leftMargin: ExLooks.spacing.l
                anchors.rightMargin: ExLooks.spacing.l
                spacing: ExLooks.spacing.l

                ExGlyph {
                    visible: root.glyph.length > 0
                    text: root.glyph
                    size: 20
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    ExText {
                        Layout.fillWidth: true
                        text: root.text
                    }
                    ExText {
                        Layout.fillWidth: true
                        visible: root.description.length > 0
                        text: root.description
                        role: "caption"
                        dim: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                }
                Row {
                    id: controlSlot
                    Layout.alignment: Qt.AlignVCenter
                    spacing: ExLooks.spacing.s
                }
                ExGlyph {
                    text: "expand_more"
                    size: 18
                    color: ExLooks.colors.textDim
                    rotation: root.expanded ? 180 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: ExLooks.motion.normal
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // Opens downwards from under the header, the rows drawn in place and
    // uncovered rather than stretched.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.expanded ? frame.height - 1 : 0
        clip: true
        visible: Layout.preferredHeight > 0

        Behavior on Layout.preferredHeight {
            NumberAnimation {
                duration: ExLooks.motion.normal
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            id: frame

            // Up by one, so its top edge lies on the header's bottom one.
            y: -1
            width: parent.width
            height: body.implicitHeight + 1
            color: ExLooks.colors.surface
            border.width: 1
            border.color: ExLooks.colors.hairline
            bottomLeftRadius: ExLooks.radius.card
            bottomRightRadius: ExLooks.radius.card

            // At the frame's top, so the rule over the first row falls under
            // the clip and the header's own edge is the only line there.
            ColumnLayout {
                id: body
                width: parent.width
                spacing: 0
            }
        }
    }
}
