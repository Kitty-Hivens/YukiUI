pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

/**
 * The grid the cards sit on.
 *
 * Cards hold coordinates rather than an order, the way tiles do on the Start
 * screen this borrows from: a tile there carries `Column` and `Row` within a group
 * of a fixed cell width, so it stays where it was put and a gap beside it is a
 * legitimate arrangement rather than something to be closed up.
 *
 * A card is one or two columns wide and as many rows tall as its contents need.
 * Dropping one onto occupied cells pushes what was there far enough down to fit,
 * which is the "make room" of the same Start screen.
 */
Item {
    id: root

    required property int columns
    required property int columnWidth
    required property int gutter

    /// Height of one row of the grid. Cards are measured in whole rows so that a
    /// card can be placed under another without overlapping it.
    readonly property int rowHeight: Math.round(BoardLooks.unit * 2)

    /// Across, the grid steps by a segment rather than by a whole column, so a card
    /// one column wide has a place halfway between two columns as well as on each of
    /// them. Everything horizontal below counts in segments.
    readonly property int cells: root.columns * BoardLooks.segments
    readonly property real pitch: (root.columnWidth + root.gutter) / BoardLooks.segments

    /// The card being carried, if any: it follows the pointer instead of the grid.
    property Item carried: null
    /// Where the carried card would land, in cells. Negative column means nowhere.
    property int dropColumn: -1
    property int dropRow: 0
    property int dropSpan: BoardLooks.segments
    property int dropRows: 1

    implicitHeight: root.usedRows * root.rowHeight
    property int usedRows: 1

    function cellX(cell) {
        return Math.round(cell * root.pitch);
    }

    function spanWidth(span) {
        return Math.round(span * root.pitch) - root.gutter;
    }

    /// The fewest rows a card can be given: enough for what it draws.
    function minRowsFor(item) {
        return root.rowsForHeight(item.naturalHeight);
    }

    /// As many rows as the card was dragged to, and never fewer than it needs.
    function rowsFor(item) {
        return Math.max(root.minRowsFor(item), BoardState.rowsOf(item.cardId));
    }

    function relayoutLater() {
        relayoutSoon.restart();
    }

    function rowsForHeight(height) {
        return Math.max(1, Math.ceil((height + root.gutter) / root.rowHeight));
    }

    function cardItems() {
        const byId = ({});
        for (const child of root.children) {
            if (child.cardId !== undefined && child.visible)
                byId[child.cardId] = child;
        }
        return BoardState.pinnedCards.map(id => byId[id]).filter(item => item !== undefined);
    }

    function spanOf(item) {
        return Math.min(BoardState.spanOf(item.cardId), root.cells);
    }

    /// Cards with their cells, in the order they are listed. A card without a
    /// placement takes the first free spot, and one whose placement no longer fits
    /// the number of columns is pulled back inside.
    function placedCards() {
        const taken = ({});
        const mark = (column, row, span, rows) => {
            for (var c = 0; c < span; c++)
                for (var r = 0; r < rows; r++) taken[`${column + c},${row + r}`] = true;
        };
        const free = (column, row, span, rows) => {
            if (column < 0 || column + span > root.cells || row < 0)
                return false;
            for (var c = 0; c < span; c++)
                for (var r = 0; r < rows; r++)
                    if (taken[`${column + c},${row + r}`])
                        return false;
            return true;
        };

        const placed = [];
        for (const item of root.cardItems()) {
            const span = root.spanOf(item);
            const rows = root.rowsFor(item);
            const wanted = BoardState.placementOf(item.cardId);

            var column = wanted ? Math.min(wanted.column, root.cells - span) : -1;
            var row = wanted ? wanted.row : -1;

            if (column < 0 || row < 0 || !free(column, row, span, rows)) {
                // First free spot, scanning row by row.
                var found = false;
                for (var r = 0; !found && r < 200; r++) {
                    for (var c = 0; c + span <= root.cells; c++) {
                        if (!free(c, r, span, rows))
                            continue;
                        column = c;
                        row = r;
                        found = true;
                        break;
                    }
                }
            }

            mark(column, row, span, rows);
            placed.push({
                item: item,
                column: column,
                row: row,
                span: span,
                rows: rows
            });
        }
        return placed;
    }

    /// Where a card sits and how big it is, for a gesture that starts from its
    /// current size rather than from the pointer alone.
    function entryFor(cardId) {
        for (const entry of root.placedCards())
            if (entry.item.cardId === cardId)
                return entry;
        return null;
    }

    function relayout() {
        var bottom = 1;
        for (const entry of root.placedCards()) {
            entry.item.width = root.spanWidth(entry.span);
            entry.item.height = entry.rows * root.rowHeight - root.gutter;
            bottom = Math.max(bottom, entry.row + entry.rows);
            if (entry.item === root.carried)
                continue;
            entry.item.x = root.cellX(entry.column);
            entry.item.y = entry.row * root.rowHeight;
        }
        if (root.dropColumn >= 0)
            bottom = Math.max(bottom, root.dropRow + root.dropRows);
        root.usedRows = bottom + (BoardState.editing ? 2 : 0);
    }

    /// The cell under a point, clamped to the grid.
    function cellAt(pointX, pointY, span) {
        const column = Math.round(pointX / root.pitch);
        const row = Math.max(0, Math.round(pointY / root.rowHeight));
        return ({
                column: Math.max(0, Math.min(column, root.cells - span)),
                row: row
            });
    }

    /// Puts a card in a cell, pushing whatever is in the way far enough down to make
    /// room for it. Used both by a card carried across the board and by one carried
    /// in from the picker.
    function placeCard(cardId, column, row, span, rows) {
        var entries = [];
        for (const entry of root.placedCards()) {
            if (entry.item.cardId === cardId)
                continue;
            const overlapsColumns = entry.column < column + span && column < entry.column + entry.span;
            const overlapsRows = entry.row < row + rows && row < entry.row + entry.rows;
            const pushed = overlapsColumns && overlapsRows ? row + rows : entry.row;
            entries.push(`${entry.item.cardId}:${entry.column},${pushed}`);
        }
        entries.push(`${cardId}:${column},${row}`);
        BoardState.setPlacements(entries);
    }

    function dropCarried() {
        if (root.dropColumn < 0 || !root.carried)
            return;
        root.placeCard(root.carried.cardId, root.dropColumn, root.dropRow, root.dropSpan, root.dropRows);
    }

    // Laying out again is deferred so that a burst of changes settles into one pass.
    // A timer rather than Qt.callLater: this dies with the board, and a call that
    // outlives it lands in a context that no longer has these functions.
    Timer {
        id: relayoutSoon
        interval: 0
        onTriggered: root.relayout()
    }

    Component.onCompleted: BoardState.grid = root
    Component.onDestruction: {
        if (BoardState.grid === root)
            BoardState.grid = null;
    }

    onWidthChanged: root.relayout()
    onColumnsChanged: root.relayout()
    onCarriedChanged: root.relayout()
    onDropColumnChanged: relayoutSoon.restart()
    onDropRowChanged: relayoutSoon.restart()
    onDropRowsChanged: relayoutSoon.restart()

    Connections {
        target: BoardState
        function onPinnedCardsChanged() {
            relayoutSoon.restart();
        }
        function onPlacementsChanged() {
            relayoutSoon.restart();
        }
        function onSizesChanged() {
            relayoutSoon.restart();
        }
        function onEditingChanged() {
            relayoutSoon.restart();
        }
    }

    // Where the carried card will land.
    Rectangle {
        z: -1
        visible: root.dropColumn >= 0
        x: root.cellX(root.dropColumn)
        y: root.dropRow * root.rowHeight
        width: root.spanWidth(root.dropSpan)
        height: root.dropRows * root.rowHeight - root.gutter
        radius: Looks.radius.medium
        color: "transparent"
        border.width: 1
        border.color: Looks.colors.accent
    }

    Repeater {
        model: ScriptModel {
            values: BoardState.pinnedCards
        }
        delegate: WidgetCardChooser {}
        onItemAdded: relayoutSoon.restart()
        onItemRemoved: relayoutSoon.restart()
    }
}
