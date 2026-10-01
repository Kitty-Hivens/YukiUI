import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.experimental.looks

// One setting, the way Windows 11 lays one out: a glyph, a name with a line
// under it saying what it does, and the control at the far end. A card that
// leads somewhere has a chevron in place of a control and answers a click.
AbstractButton {
    id: root

    property string glyph: ""
    property string description: ""
    /** Leads to another page rather than holding a control. */
    property bool leads: false
    /** A row inside a SettingsExpander: no card of its own, a rule above it,
     *  and its text in line with the text of the expander's header. */
    property bool flat: false
    /** The control, at the far end. */
    default property alias control: controlSlot.data

    implicitHeight: Math.max(68, row.implicitHeight + 2 * ExLooks.spacing.m)
    hoverEnabled: root.leads
    focusPolicy: root.leads ? Qt.StrongFocus : Qt.NoFocus

    background: Rectangle {
        radius: root.flat ? 0 : ExLooks.radius.card
        color: root.flat ? "transparent" : ExLooks.colors.surface
        border.width: root.flat ? 0 : 1
        border.color: ExLooks.colors.hairline

        Rectangle {
            visible: root.flat
            width: parent.width
            height: 1
            color: ExLooks.colors.hairline
        }

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: root.leads && root.hovered
            pressed: root.leads && root.down
        }
    }

    contentItem: Item {
        RowLayout {
            id: row

            anchors.fill: parent
            // Past where the header's glyph stands, when a flat row has none.
            anchors.leftMargin: root.flat && root.glyph.length === 0 ? 2 * ExLooks.spacing.l + 20 : ExLooks.spacing.l
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
                visible: root.leads
                text: "chevron_right"
                size: 18
                color: ExLooks.colors.textDim
            }
        }
    }
}
