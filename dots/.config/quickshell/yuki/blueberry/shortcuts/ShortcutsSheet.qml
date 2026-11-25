pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

/**
 * The plate with the groups on it, in as many columns as it is wide enough for,
 * read down one column and on to the next.
 */
ExSurface {
    id: root

    required property var groups
    /** As large as it may be. */
    required property real roomWidth
    required property real roomHeight

    signal closeAsked

    readonly property var metrics: ExLooks.settings
    readonly property real padding: ExLooks.spacing.xl
    readonly property real columnGap: ExLooks.spacing.m
    readonly property int columns: Math.max(1, Math.min(3, Math.floor((root.roomWidth - 2 * root.padding + root.columnGap) / (344 + root.columnGap))))
    readonly property real columnWidth: Math.min(424, (root.roomWidth - 2 * root.padding - (root.columns - 1) * root.columnGap) / root.columns)

    /** On a small screen the rows stand closer. */
    readonly property bool dense: root.roomHeight < 860
    readonly property real rowHeight: root.dense ? 36 : 40

    function heightOf(group: var): real {
        return 60 + group.rows.reduce((height, row) => height + (row.note.length > 0 ? root.rowHeight + 18 : root.rowHeight), 0);
    }

    /**
     * The groups of each column, left to right, in their order, parted where
     * the tallest column comes out the shortest.
     */
    readonly property var laidOut: {
        const heights = root.groups.map(group => root.heightOf(group) + root.columnGap);
        const best = (from, columns) => {
            const rest = heights.slice(from).reduce((sum, height) => sum + height, 0);
            if (columns === 1 || from >= heights.length)
                return { tallest: rest, cuts: [] };
            let found = null;
            let mine = 0;
            for (let to = from + 1; to <= heights.length; to++) {
                mine += heights[to - 1];
                const after = best(to, columns - 1);
                const tallest = Math.max(mine, after.tallest);
                if (!found || tallest < found.tallest)
                    found = { tallest: tallest, cuts: [to, ...after.cuts] };
            }
            return found;
        };
        const bounds = [0, ...best(0, root.columns).cuts, root.groups.length];
        return bounds.slice(0, -1).map((from, index) => root.groups.slice(from, bounds[index + 1]));
    }

    /** Taller than there is room for, and so scrolled. */
    readonly property bool overflows: scroller.contentHeight > scroller.height + 1

    function scrollBy(step: real) {
        scroller.contentY = Math.max(0, Math.min(Math.max(0, scroller.contentHeight - scroller.height), scroller.contentY + step));
    }
    function page(): real {
        return scroller.height * 0.8;
    }

    color: root.metrics.pane
    elevation: 2
    width: 2 * root.padding + root.columns * root.columnWidth + (root.columns - 1) * root.columnGap
    height: Math.min(root.roomHeight, header.height + columnsRow.implicitHeight + root.padding)

    Item {
        id: header

        width: parent.width
        height: 88

        Column {
            x: root.padding
            anchors.verticalCenter: parent.verticalCenter
            width: close.x - x - ExLooks.spacing.m
            spacing: 2

            ExText {
                width: parent.width
                text: Translation.tr("Keys and mouse")
                font.pixelSize: 22
                font.weight: ExLooks.font.weightTitle
            }
            ExText {
                width: parent.width
                text: Translation.tr("Super is the key with the Windows logo on most keyboards. Tapped on its own, it opens the search.")
                font.pixelSize: ExLooks.font.label
                dim: true
            }
        }
        ExToolButton {
            id: close

            anchors.right: parent.right
            anchors.rightMargin: root.padding - 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: "close"
            onClicked: root.closeAsked()
        }
    }

    Flickable {
        id: scroller

        y: header.height
        width: parent.width
        height: parent.height - y - 1
        contentHeight: columnsRow.implicitHeight + root.padding - 1
        boundsBehavior: Flickable.StopAtBounds
        clip: root.overflows

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Row {
            id: columnsRow

            x: root.padding
            spacing: root.columnGap

            Repeater {
                model: root.laidOut

                Column {
                    id: column

                    required property var modelData

                    width: root.columnWidth
                    spacing: root.columnGap

                    Repeater {
                        model: column.modelData

                        Group {}
                    }
                }
            }
        }
    }

    // There is more further down.
    Rectangle {
        visible: root.overflows && !scroller.atYEnd
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        x: root.padding
        width: parent.width - 2 * root.padding
        height: 40
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(root.metrics.pane.r, root.metrics.pane.g, root.metrics.pane.b, 0) }
            GradientStop { position: 0.85; color: root.metrics.pane }
        }
    }

    component Group: Rectangle {
        id: group

        required property var modelData

        width: root.columnWidth
        height: rows.y + rows.implicitHeight + ExLooks.spacing.s
        radius: root.metrics.plateRadius
        color: root.metrics.plate

        SettingsChip {
            id: chip

            x: root.metrics.rowPadding
            y: ExLooks.spacing.m
            size: 28
            glyph: group.modelData.glyph
            hue: group.modelData.hue
        }
        ExText {
            anchors.verticalCenter: chip.verticalCenter
            x: chip.x + chip.width + ExLooks.spacing.m
            text: group.modelData.title
            font.pixelSize: root.metrics.body
            font.weight: ExLooks.font.weightTitle
        }

        Column {
            id: rows

            y: chip.y + chip.height + ExLooks.spacing.xs
            width: parent.width

            Repeater {
                model: group.modelData.rows

                KeyRow {}
            }
        }
    }

    // What is done, and the keys that do it at the far end.
    component KeyRow: Item {
        id: keyRow

        required property var modelData

        width: root.columnWidth
        height: Math.max(root.rowHeight, texts.implicitHeight + (root.dense ? ExLooks.spacing.s : ExLooks.spacing.m))

        Column {
            id: texts

            anchors.verticalCenter: parent.verticalCenter
            x: root.metrics.rowPadding
            width: caps.x - x - ExLooks.spacing.m
            spacing: 1

            ExText {
                width: parent.width
                text: keyRow.modelData.text
                font.pixelSize: root.metrics.body
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }
            ExText {
                width: parent.width
                visible: keyRow.modelData.note.length > 0
                text: keyRow.modelData.note
                font.pixelSize: root.metrics.small
                wrapMode: Text.Wrap
                maximumLineCount: 4
                dim: true
            }
        }
        Row {
            id: caps

            anchors.right: parent.right
            anchors.rightMargin: root.metrics.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: keyRow.modelData.caps

                ExKeycap {
                    required property var modelData

                    text: modelData.text ?? ""
                    glyphs: modelData.glyphs ?? []
                    mouse: modelData.mouse ?? ""
                }
            }
        }
    }
}
