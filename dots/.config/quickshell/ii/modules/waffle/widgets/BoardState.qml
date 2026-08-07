pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.waffle.widgets
import qs.services

/**
 * What the board is doing and what can be done to it.
 *
 * The cards are laid out by a repeater over a list in the configuration, so
 * arranging them is arranging that list. Editing is a state of the board rather
 * than of any one card, which is why it lives here and not in the panel.
 */
Singleton {
    id: root

    property bool editing: false

    /// What the board currently measures, so a window standing beside it knows
    /// where the board ends.
    property int boardWidth: 0
    property int boardHeight: 0

    /// What is being carried out of the picker, drawn by the picker's window rather
    /// than inside its pane -- a pane masks what it holds, and a card on its way to
    /// the board is outside it.
    property string carriedOffer: ""
    property real carriedX: 0
    property real carriedY: 0
    property real carriedWidth: 0
    property real carriedHeight: 0

    /// Where the picker's panel is drawn, in the coordinates both windows share, so
    /// a card dragged over it can be given back rather than dropped on the board.
    property rect pickerArea: Qt.rect(0, 0, 0, 0)
    /// Whether the card being carried is over the picker, which the picker shows.
    property bool returning: false

    function overPicker(pointX, pointY) {
        return root.pickerArea.width > 0 && pointX >= root.pickerArea.x && pointX <= root.pickerArea.x + root.pickerArea.width && pointY >= root.pickerArea.y && pointY <= root.pickerArea.y + root.pickerArea.height;
    }

    /// The picker's window, so the board's focus grab counts it as part of itself
    /// and a press on it is not a press past the board.
    property var pickerWindow: null
    /// Where the board's own panel starts inside its window.
    property int boardTop: 0

    /// The grid itself, handed over by the board so a widget carried in from the
    /// picker window can be aimed at a cell in it.
    property Item grid: null

    function cellAtBoardPoint(pointX, pointY, cardId, cardHeight) {
        if (!root.grid)
            return null;
        const inGrid = root.grid.mapFromItem(null, pointX, pointY);
        // Off the board entirely -- above it, below its last row, or past its right
        // edge -- means nowhere. Within it, the grid clamps for itself.
        if (inGrid.y < 0 || inGrid.y > root.grid.height + root.grid.rowHeight)
            return null;
        if (inGrid.x < -root.grid.columnWidth / 2 || inGrid.x > root.grid.width + root.grid.columnWidth / 2)
            return null;
        const span = Math.min(root.spanOf(cardId), root.grid.cells);
        const carriedHeight = cardHeight ?? root.grid.rowHeight;
        const cell = root.grid.cellAt(inGrid.x - root.grid.spanWidth(span) / 2, inGrid.y - carriedHeight / 2, span);
        return ({
                column: cell.column,
                row: cell.row,
                span: span,
                rows: root.grid.rowsForHeight(carriedHeight)
            });
    }

    function aimDrop(cell) {
        if (!root.grid)
            return;
        if (!cell) {
            root.grid.dropColumn = -1;
            return;
        }
        root.grid.dropSpan = cell.span;
        root.grid.dropRows = cell.rows ?? 1;
        root.grid.dropColumn = cell.column;
        root.grid.dropRow = cell.row;
    }

    /// The cell currently marked out on the board, if any.
    function aimedCell() {
        if (!root.grid || root.grid.dropColumn < 0)
            return null;
        return ({
                column: root.grid.dropColumn,
                row: root.grid.dropRow,
                span: root.grid.dropSpan,
                rows: root.grid.dropRows
            });
    }

    /// A widget carried in from the picker lands the same way a card already on the
    /// board does: what is in the way is pushed down far enough to fit.
    function dropOnBoard(cardId, cell) {
        if (!root.grid)
            return;
        root.addCard(cardId);
        root.grid.placeCard(cardId, cell.column, cell.row, cell.span, cell.rows ?? 1);
    }

    /// The width the board was last left at, dragged by its edge. Columns follow
    /// from it: as many as fit, rather than a choice between two sizes.
    property int width: Persistent.states.widgets.width
    onWidthChanged: Persistent.states.widgets.width = root.width

    function columnsFor(width) {
        const room = (width > 0 ? width : BoardLooks.widthForColumns(2)) - BoardLooks.padding * 2;
        return Math.max(1, Math.floor((room + BoardLooks.gutter) / (BoardLooks.columnWidth + BoardLooks.gutter)));
    }

    /// As many columns as the screen has room for, told by the board while it is
    /// open. The count itself follows the width whether the board is there or not,
    /// so a width set from elsewhere is read the same way.
    property int columnCeiling: 4
    readonly property int columns: Math.min(root.columnsFor(root.width), root.columnCeiling)

    /// Read from the width rather than remembered beside it, so the button that
    /// snaps between narrow and wide always knows which way it is going.
    readonly property bool wide: root.columns >= 3

    /// The two widths the corner button snaps between. Worked out here rather than
    /// handed in by the board, which exists only while the board is open.
    function toggleWide() {
        root.width = BoardLooks.widthForColumns(root.wide ? 2 : 3);
    }

    /// Everything that can be put on the board, in the order it is offered.
    readonly property list<string> knownCards: ["weather", "calendar", "todo"]

    readonly property list<string> pinnedCards: Config.options?.waffles.widgets.cards ?? []
    readonly property list<string> unpinnedCards: root.knownCards.filter(card => root.pinnedCards.indexOf(card) === -1)

    function nameOf(cardId) {
        switch (cardId) {
        case "weather":
            return Translation.tr("Weather");
        case "calendar":
            return Translation.tr("Calendar");
        case "todo":
            return Translation.tr("To do");
        }
        return cardId;
    }

    function iconOf(cardId) {
        switch (cardId) {
        case "weather":
            return "weather-sunny";
        case "calendar":
            return "calendar-add";
        case "todo":
            return "checkmark";
        }
        return "apps";
    }

    /// How big each card is, in cells, kept as "id:segmentsXrows". Any rectangle the
    /// board has room for: a card is dragged to its size by the corner rather than
    /// picked from a set of sizes somebody else chose. A column is BoardLooks.segments
    /// segments across, so a card can be a column and a half wide.
    readonly property list<string> sizes: Config.options?.waffles.widgets.sizes ?? []
    /// Boards arranged before sizes existed said only which cards were two columns
    /// wide. Read so those boards come back the way they were left.
    readonly property list<string> wideCards: Config.options?.waffles.widgets.wideCards ?? []

    function sizeOf(cardId) {
        for (const entry of root.sizes) {
            const parts = entry.split(":");
            if (parts[0] !== cardId || parts.length < 2)
                continue;
            const at = parts[1].split("x");
            const columns = parseInt(at[0]);
            const rows = parseInt(at[1]);
            if (columns > 0 && rows > 0)
                return ({
                        columns: columns,
                        rows: rows
                    });
        }
        return null;
    }

    /// How many segments across a card is. Rows are the board's to work out: a card
    /// is never shorter than its contents, whatever size it was left at.
    function spanOf(cardId) {
        const size = root.sizeOf(cardId);
        if (size)
            return size.columns;
        return BoardLooks.segments * (root.wideCards.indexOf(cardId) !== -1 ? 2 : 1);
    }

    function rowsOf(cardId) {
        return root.sizeOf(cardId)?.rows ?? 0;
    }

    function setSize(cardId, columns, rows) {
        const others = root.sizes.filter(entry => entry.split(":")[0] !== cardId);
        Config.options.waffles.widgets.sizes = others.concat([`${cardId}:${columns}x${rows}`]);
    }

    function forgetSize(cardId) {
        Config.options.waffles.widgets.sizes = root.sizes.filter(entry => entry.split(":")[0] !== cardId);
    }

    /// Where the cards sit. Kept as "id:column,row" so a card holds its place
    /// rather than being packed against its neighbours -- the grid a card is put
    /// on is the grid it stays on, gaps and all.
    readonly property list<string> placements: Config.options?.waffles.widgets.placements ?? []

    function placementOf(cardId) {
        for (const entry of root.placements) {
            const parts = entry.split(":");
            if (parts[0] !== cardId || parts.length < 2)
                continue;
            const at = parts[1].split(",");
            return ({
                    column: parseInt(at[0]),
                    row: parseInt(at[1])
                });
        }
        return null;
    }

    function setPlacement(cardId, column, row) {
        const others = root.placements.filter(entry => entry.split(":")[0] !== cardId);
        Config.options.waffles.widgets.placements = others.concat([`${cardId}:${column},${row}`]);
    }

    function setPlacements(entries) {
        Config.options.waffles.widgets.placements = entries;
    }

    function forgetPlacement(cardId) {
        Config.options.waffles.widgets.placements = root.placements.filter(entry => entry.split(":")[0] !== cardId);
    }

    function addCard(cardId) {
        if (root.pinnedCards.indexOf(cardId) !== -1)
            return;
        Config.options.waffles.widgets.cards = root.pinnedCards.concat([cardId]);
    }

    function removeCard(cardId) {
        Config.options.waffles.widgets.cards = root.pinnedCards.filter(card => card !== cardId);
        root.forgetPlacement(cardId);
        // Size belongs to a card on the board; the offer in the picker is one column
        // wide, and a size left behind would aim it as though it were still that big.
        root.forgetSize(cardId);
        Config.options.waffles.widgets.wideCards = root.wideCards.filter(card => card !== cardId);
    }

    /// Puts a card where another one is, which is what dropping it there means.
    function moveCardTo(cardId, index) {
        const cards = root.pinnedCards.slice();
        const from = cards.indexOf(cardId);
        if (from === -1 || index < 0 || index >= cards.length || from === index)
            return;
        cards.splice(index, 0, cards.splice(from, 1)[0]);
        Config.options.waffles.widgets.cards = cards;
    }

    /// Moves a card by one place, for the keyboard.
    function moveCard(cardId, delta) {
        const cards = root.pinnedCards.slice();
        const from = cards.indexOf(cardId);
        const to = from + delta;
        if (from === -1 || to < 0 || to >= cards.length)
            return;
        cards.splice(to, 0, cards.splice(from, 1)[0]);
        Config.options.waffles.widgets.cards = cards;
    }

    function canMove(cardId, delta) {
        const index = root.pinnedCards.indexOf(cardId);
        const target = index + delta;
        return index !== -1 && target >= 0 && target < root.pinnedCards.length;
    }
}
