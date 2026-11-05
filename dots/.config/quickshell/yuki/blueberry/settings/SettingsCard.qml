import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

import qs.blueberry.looks

// One setting: a glyph on a disc, its name with a line saying what it does,
// and the control at the far end. In a group it is a row of the group's
// plate, parted from the row above by a rule; on its own it is a plate of its
// own. One that leads somewhere ends in a chevron and answers a click.
AbstractButton {
    id: root

    ExPrimaryOnly {
        z: 1
    }

    property string glyph: ""
    /** A picture in place of the glyph, an application's icon say. */
    property string iconSource: ""
    /** The disc's hue, for a row standing for a category; plain otherwise. */
    property real hue: -1
    property string description: ""
    /** Leads to another page rather than holding a control. */
    property bool leads: false
    /** A row inside a SettingsExpander, which draws the plate itself. */
    property bool flat: false
    /** In a group, drawn on the group's plate. */
    readonly property bool grouped: root.parent?.settingsRows === true
    /** The control, at the far end. */
    default property alias control: controlSlot.data

    readonly property var metrics: ExLooks.settings
    readonly property bool showsGlyph: root.glyph.length > 0 || root.iconSource.length > 0
    /** The first row the group shows, with no rule above it, and the last; their corners are the plate's. */
    readonly property bool firstShown: root.grouped ? root.parent?.firstRow === root
        : root.flat ? Array.from(root.parent?.children ?? []).find(sibling => sibling.visible && sibling.flat === true) === root
        : true
    readonly property bool lastShown: !root.grouped || root.parent?.lastRow === root
    onVisibleChanged: root.parent?.placeRows?.()
    readonly property bool plain: root.grouped || root.flat
    /** Where the text starts, for the rule to start there too. */
    readonly property real textX: root.leftEdge + (root.showsGlyph ? root.metrics.rowChip + root.metrics.rowPadding : 0)
    /** A row an expander opens onto starts under the text of the row it opens from. */
    readonly property real leftEdge: root.flat ? 2 * root.metrics.rowPadding + root.metrics.rowChip : root.metrics.rowPadding

    implicitHeight: Math.max(root.metrics.rowHeight + (root.description.length > 0 ? 8 : 0), row.implicitHeight + 2 * ExLooks.spacing.m)

    // Inside the row, whose neighbours would cover what stood outside it.
    ExFocusRing {
        anchors.margins: 0
        cornerRadius: 4
    }

    hoverEnabled: root.leads
    focusPolicy: root.leads ? Qt.StrongFocus : Qt.NoFocus

    background: Rectangle {
        radius: root.plain ? 0 : root.metrics.plateRadius
        color: root.plain ? "transparent" : root.metrics.plate

        // The wash under the pointer, rounded where the row meets the
        // plate's corners and square between rows.
        Rectangle {
            anchors.fill: parent
            readonly property real corner: root.grouped ? root.metrics.plateRadius : parent.radius
            topLeftRadius: !root.grouped || root.firstShown ? corner : 0
            topRightRadius: !root.grouped || root.firstShown ? corner : 0
            bottomLeftRadius: !root.grouped || root.lastShown ? corner : 0
            bottomRightRadius: !root.grouped || root.lastShown ? corner : 0
            color: ExLooks.colors.text
            opacity: !root.leads ? 0 : root.down ? ExLooks.colors.pressOpacity : root.hovered ? ExLooks.colors.hoverOpacity : 0

            Behavior on opacity {
                NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }
        }
        Rectangle {
            visible: root.plain && !root.firstShown
            x: root.textX
            width: parent.width - x
            height: 1
            color: root.metrics.rule
        }
    }

    contentItem: Item {
        RowLayout {
            id: row

            anchors.fill: parent
            anchors.leftMargin: root.leftEdge
            anchors.rightMargin: root.metrics.rowPadding
            spacing: root.metrics.rowPadding

            SettingsChip {
                visible: root.showsGlyph && root.iconSource.length === 0
                glyph: root.glyph
                hue: root.hue
            }
            IconImage {
                visible: root.iconSource.length > 0
                implicitSize: root.metrics.rowChip
                source: root.iconSource
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
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    font.pixelSize: root.metrics.small
                    dim: true
                }
            }
            Row {
                id: controlSlot

                Layout.alignment: Qt.AlignVCenter
                spacing: ExLooks.spacing.s
                // A row places its children along it only, so one shorter
                // than the rest stood at the top, a switch beside a button
                // say. Each is put on the row's middle.
                onPositioningComplete: {
                    for (const child of controlSlot.children)
                        child.y = Math.round((controlSlot.height - child.height) / 2);
                }
            }
            ExGlyph {
                visible: root.leads
                text: "chevron_right"
                size: 20
                color: ExLooks.colors.textDim
            }
        }
    }
}
