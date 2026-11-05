import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.blueberry.looks

// A setting with others that belong to it: a head like a row's, with its own
// control and a chevron, and under it the rows it opens onto, parted by rules.
// In a group it is a row of the group's plate; on its own it is a plate of its
// own. The rows are SettingsCards with `flat` set.
ColumnLayout {
    id: root

    property string glyph: ""
    property string text: ""
    property string description: ""
    property bool expanded: false
    /** The header's control, at its far end before the chevron. */
    property alias control: controlSlot.data
    default property alias rows: body.data

    readonly property var metrics: ExLooks.settings
    /** In a group, drawn on the group's plate. */
    readonly property bool grouped: root.parent?.settingsRows === true
    readonly property bool firstShown: !root.grouped || root.parent?.firstRow === root
    readonly property bool lastShown: !root.grouped || root.parent?.lastRow === root
    readonly property real textX: root.metrics.rowPadding + (root.glyph.length > 0 ? root.metrics.rowChip + root.metrics.rowPadding : 0)
    onVisibleChanged: root.parent?.placeRows?.()

    spacing: 0

    AbstractButton {
        id: header

        ExPrimaryOnly {
            z: 1
        }

        readonly property real topRadius: root.firstShown ? root.metrics.plateRadius : 0
        readonly property real bottomRadius: root.lastShown && !root.expanded ? root.metrics.plateRadius : 0

        Layout.fillWidth: true
        implicitHeight: Math.max(root.metrics.rowHeight + (root.description.length > 0 ? 8 : 0), headerRow.implicitHeight + 2 * ExLooks.spacing.m)
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        ExFocusRing {
            anchors.margins: 0
            cornerRadius: 4
        }

        background: Rectangle {
            color: root.grouped ? "transparent" : root.metrics.plate
            topLeftRadius: header.topRadius
            topRightRadius: header.topRadius
            bottomLeftRadius: header.bottomRadius
            bottomRightRadius: header.bottomRadius

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: header.hovered
                pressed: header.down
                topLeftRadius: header.topRadius
                topRightRadius: header.topRadius
                bottomLeftRadius: header.bottomRadius
                bottomRightRadius: header.bottomRadius
            }
            Rectangle {
                visible: !root.firstShown
                x: root.textX
                width: parent.width - x
                height: 1
                color: root.metrics.rule
            }
        }

        contentItem: Item {
            RowLayout {
                id: headerRow

                anchors.fill: parent
                anchors.leftMargin: root.metrics.rowPadding
                anchors.rightMargin: root.metrics.rowPadding
                spacing: root.metrics.rowPadding

                SettingsChip {
                    visible: root.glyph.length > 0
                    glyph: root.glyph
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    ExText {
                        Layout.fillWidth: true
                        text: root.text
                        font.pixelSize: root.metrics.body
                    }
                    ExText {
                        Layout.fillWidth: true
                        visible: root.description.length > 0
                        text: root.description
                        font.pixelSize: root.metrics.small
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
        Layout.preferredHeight: root.expanded ? frame.height : 0
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

            width: parent.width
            height: body.implicitHeight
            color: root.grouped ? "transparent" : root.metrics.plate
            bottomLeftRadius: root.lastShown ? root.metrics.plateRadius : 0
            bottomRightRadius: root.lastShown ? root.metrics.plateRadius : 0

            ColumnLayout {
                id: body
                width: parent.width
                spacing: 0
            }
            // Between the head and the first row, whose own rule it leaves out.
            Rectangle {
                x: root.textX
                width: parent.width - x
                height: 1
                color: root.metrics.rule
            }
        }
    }
}
