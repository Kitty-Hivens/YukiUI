import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// A label and the settings under it, on one plate: rows parted by rules, the
// plate set apart from the page by its tone alone.
ColumnLayout {
    id: root

    property string title: ""
    default property alias cards: column.data

    readonly property var metrics: ExLooks.settings

    spacing: root.metrics.labelGap

    ExText {
        visible: root.title.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: root.metrics.rowPadding
        text: root.title
        font.pixelSize: root.metrics.small
        font.weight: ExLooks.font.weightTitle
        dim: true
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: column.implicitHeight
        radius: root.metrics.plateRadius
        color: root.metrics.plate

        ColumnLayout {
            id: column

            /** Read by the rows: they are drawn on this plate rather than as plates. */
            readonly property bool settingsRows: true
            /** The first and the last row shown, whose corners are the plate's. */
            property Item firstRow: null
            property Item lastRow: null

            // By where they stand once laid out, not by the order of the
            // children: rows a Repeater makes join the list after the rest.
            function placeRows() {
                Qt.callLater(() => {
                    const rows = Array.from(column.children).filter(child => child.visible && child.grouped !== undefined).sort((a, b) => a.y - b.y);
                    column.firstRow = rows[0] ?? null;
                    column.lastRow = rows[rows.length - 1] ?? null;
                });
            }
            onImplicitHeightChanged: column.placeRows()

            width: parent.width
            spacing: 0

            // Anything else put in a group, a note or a button, stands in from
            // the plate's edges as a row's text does. A Repeater is no item to
            // place; what it makes is.
            onChildrenChanged: {
                for (const child of Array.from(column.children)) {
                    if (child instanceof Repeater)
                        continue;
                    // A row runs the plate's width.
                    if (child.grouped !== undefined) {
                        child.Layout.fillWidth = true;
                        continue;
                    }
                    child.Layout.leftMargin = root.metrics.rowPadding;
                    child.Layout.rightMargin = root.metrics.rowPadding;
                    child.Layout.topMargin = ExLooks.spacing.m;
                    child.Layout.bottomMargin = ExLooks.spacing.m;
                }
                column.placeRows();
            }
            // A row coming or going from view changes which is first and last.
            Component.onCompleted: column.placeRows()
        }
    }
}
