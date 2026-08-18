pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import qs.waffle.widgets

/**
 * One card on the board: a heading set in caps, a reading beside it, a rule under
 * both, and whatever the card puts below that. Corner marks stand in for a border.
 *
 * While the board is being arranged the card is picked up whole and carried, and
 * every edge and corner of it is a size handle. Neither gesture decides anything
 * until it is let go: what it would do is marked out on the board first.
 */
Rectangle {
    id: root

    required property string cardId
    property string title: ""
    property string iconName: "apps"
    property color foregroundColor: Looks.colors.fg
    /// Small monospaced text along the heading -- a reading, not a label.
    property string readout: ""
    /// A card that has somewhere to send you says so along its bottom edge.
    property string actionText: ""
    property bool unpinnable: true
    /// A card shown as a sample in the picker is not on the board: it carries no
    /// arranging controls and its own contents do not take the pointer.
    property bool sample: false
    signal actionTriggered
    default property alias cardContent: contentArea.data

    readonly property bool arrangeable: root.unpinnable && BoardState.editing && !root.sample

    /// The least the card can be drawn in. Its actual height is however many rows it
    /// was dragged to cover, which the board sets.
    readonly property int naturalHeight: contentColumn.implicitHeight + BoardLooks.cardPadding * 2
    /// Set by the board the first time it puts the card somewhere. Until then the
    /// card sits at the corner, and gliding out of the corner is what a board looks
    /// like when it twitches into place.
    property bool placed: false
    readonly property bool glides: root.placed && (root.parent?.animating ?? false) && !dragHandler.active

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    implicitHeight: root.naturalHeight
    height: root.naturalHeight
    color: Looks.colors.bg1
    radius: Looks.radius.medium
    /// Squeezed into fewer rows than it would like, the card keeps what it draws
    /// inside itself rather than spilling over the board's edge.
    clip: true
    /// While it is being carried the card is drawn by the window that stands over
    /// both panels, so it is not cut off at the edge of the one it is leaving.
    opacity: dragHandler.active ? 0 : 1

    // What the card draws settled into a different size; that is a re-measure of the
    // board, not a rearrangement of it.
    onNaturalHeightChanged: root.parent?.relayoutLater?.(false)

    Behavior on x {
        enabled: root.glides
        animation: Looks.transition.move.createObject(this)
    }
    Behavior on y {
        enabled: root.glides
        animation: Looks.transition.move.createObject(this)
    }

    //////////////////// Carrying ////////////////////

    /// Where the card has been dragged to, in the coordinates its window shares with
    /// the picker's. mapToItem is given the laid-out position plus the drag rather
    /// than the card's own, which already carries neither.
    function carriedCorner() {
        return root.parent.mapToItem(null, root.x + dragHandler.activeTranslation.x, root.y + dragHandler.activeTranslation.y);
    }

    function reportCarried() {
        const corner = root.carriedCorner();
        BoardState.carriedX = corner.x;
        BoardState.carriedY = corner.y;
    }

    /// The cell the card is currently over, marked out on the board so the landing
    /// place is visible before it is let go. Carried onto the picker instead, it is
    /// being given back, and no cell is marked.
    function aimAtCell() {
        const board = root.parent;
        const corner = root.carriedCorner();
        BoardState.returning = BoardState.overPicker(corner.x + root.width / 2, corner.y + root.height / 2);
        if (BoardState.returning) {
            board.dropColumn = -1;
            return;
        }
        const span = Math.min(BoardState.spanOf(root.cardId), board.cells);
        const rows = board.rowsFor(root);
        const cell = board.cellAt(root.x + dragHandler.activeTranslation.x, root.y + dragHandler.activeTranslation.y, span, rows);
        board.dropSpan = span;
        board.dropRows = rows;
        board.dropColumn = cell.column;
        board.dropRow = cell.row;
    }

    /// Everything a gesture was about to do, dropped. Used when the board stops being
    /// arranged underneath one: nothing was let go, so nothing is decided.
    function abandonGesture() {
        const board = root.parent;
        BoardState.carriedOffer = "";
        BoardState.returning = false;
        if (!board)
            return;
        board.dropColumn = -1;
        if (board.carried === root)
            board.carried = null;
        board.relayoutLater(false);
    }

    //////////////////// Sizing ////////////////////

    /// The rectangle of cells a handle has been pulled over, held inside the board
    /// and never smaller than the card's own contents. An edge on the near side moves
    /// that side and leaves the far one where it is.
    function sizeUnderGrip(gripX, gripY, translation) {
        const board = root.parent;
        const entry = board.entryFor(root.cardId);
        if (!entry)
            return null;
        // A column is the narrowest a card is drawn in; wider goes by segments, so a
        // card and a half across is a size like any other.
        const leastSpan = BoardLooks.segments;
        const leastRows = board.minRowsFor(root);

        var column = entry.column;
        var span = entry.span;
        if (gripX < 0) {
            const rightCell = entry.column + entry.span;
            const leftmost = Math.max(0, rightCell - leastSpan);
            column = Math.min(Math.max(0, Math.round((root.x + translation.x) / board.pitch)), leftmost);
            span = rightCell - column;
        } else if (gripX > 0) {
            const pulled = (root.x + root.width + translation.x - board.cellX(entry.column) + board.gutter) / board.pitch;
            span = Math.max(leastSpan, Math.min(Math.round(pulled), board.cells - entry.column));
        }

        var row = entry.row;
        var rows = entry.rows;
        if (gripY < 0) {
            const bottomRow = entry.row + entry.rows;
            const highest = Math.max(0, bottomRow - leastRows);
            row = Math.min(Math.max(0, Math.round((root.y + translation.y) / board.rowHeight)), highest);
            rows = bottomRow - row;
        } else if (gripY > 0) {
            const pulled = (root.y + root.height + translation.y - entry.row * board.rowHeight + board.gutter) / board.rowHeight;
            rows = Math.min(board.rows - entry.row, Math.max(leastRows, Math.round(pulled)));
        }

        return ({
                column: column,
                row: row,
                span: span,
                rows: rows
            });
    }

    function aimAtSize(gripX, gripY, translation) {
        const board = root.parent;
        const size = root.sizeUnderGrip(gripX, gripY, translation);
        if (!size) {
            board.dropColumn = -1;
            return;
        }
        board.dropColumn = size.column;
        board.dropRow = size.row;
        board.dropSpan = size.span;
        board.dropRows = size.rows;
    }

    function settleSize() {
        const board = root.parent;
        const size = board.dropColumn >= 0 ? ({
                    column: board.dropColumn,
                    row: board.dropRow,
                    span: board.dropSpan,
                    rows: board.dropRows
                }) : null;
        board.dropColumn = -1;
        // A card taken off the board mid-gesture has nothing left to settle, and a
        // gesture that ended where it started is not a resize -- writing that back
        // would put every card's current size into the configuration for nothing.
        // The near edges move the card as well as size it, so where it sits counts.
        const entry = size ? board.entryFor(root.cardId) : null;
        if (!entry)
            return;
        if (entry.span === size.span && entry.rows === size.rows && entry.column === size.column && entry.row === size.row)
            return;
        BoardState.setSize(root.cardId, size.span, size.rows);
        board.placeCard(root.cardId, size.column, size.row, size.span, size.rows);
    }

    //////////////////// What is drawn ////////////////////

    WCornerMarks {
        anchors.fill: parent
        anchors.margins: 6
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: BoardLooks.cardPadding
        }
        spacing: Math.round(BoardLooks.unit * 0.66)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 8

            FluentIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: root.iconName
                implicitSize: 16
                monochrome: true
                color: root.foregroundColor
            }

            WText {
                Layout.alignment: Qt.AlignVCenter
                text: root.title.toUpperCase()
                elide: Text.ElideRight
                color: root.foregroundColor
                font.pixelSize: Looks.font.pixelSize.normal
                font.weight: Looks.font.weight.strong
                font.letterSpacing: BoardLooks.headingSpacing
            }

            Item {
                Layout.fillWidth: true
            }

            WText {
                Layout.alignment: Qt.AlignVCenter
                // Out of the way while the card carries its arranging controls, which
                // sit in the same corner.
                visible: root.readout.length > 0 && !root.arrangeable
                text: root.readout
                color: ColorUtils.transparentize(root.foregroundColor, 0.45)
                font.family: BoardLooks.readoutFamily
                font.pixelSize: BoardLooks.readoutSize
                font.letterSpacing: BoardLooks.readoutSpacing
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: BoardLooks.rule
        }

        Item {
            id: contentArea
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
            // A sample in the picker shows what the card looks like; its buttons are
            // not there to be pressed, and pressing one would eat the drag.
            enabled: !root.sample
        }

        WTextButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: -4
            visible: root.actionText.length > 0
            implicitHeight: 28
            text: root.actionText
            onClicked: root.actionTriggered()
        }
    }

    // Arranging happens over the card, not inside its heading: picking it up and
    // dropping it somewhere is the whole gesture, and the readings stay put.
    DragHandler {
        id: dragHandler
        enabled: root.arrangeable && !root.sample
        target: null
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            const board = root.parent;
            // A gesture the board took away is not one the pointer finished: leaving
            // edit mode disables this handler, and that arrives here as a release.
            if (!dragHandler.active && !root.arrangeable) {
                root.abandonGesture();
                return;
            }
            if (dragHandler.active) {
                board.carried = root;
                BoardState.carriedOffer = root.cardId;
                BoardState.carriedWidth = root.width;
                BoardState.carriedHeight = root.height;
                root.reportCarried();
                root.aimAtCell();
                return;
            }
            BoardState.carriedOffer = "";
            const givenBack = BoardState.returning;
            BoardState.returning = false;
            if (givenBack) {
                // Carried onto the picker: the board is giving the card back, and it
                // is offered there again.
                board.dropColumn = -1;
                board.carried = null;
                BoardState.removeCard(root.cardId);
                return;
            }
            // Landed before the aim is cleared: the cell it drops into is the one
            // marked out on the board.
            board.dropCarried();
            board.dropColumn = -1;
            board.carried = null;
        }
        onCentroidChanged: {
            if (dragHandler.active) {
                root.reportCarried();
                root.aimAtCell();
            }
        }
        onActiveTranslationChanged: {
            if (dragHandler.active) {
                root.reportCarried();
                root.aimAtCell();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.arrangeable
        color: ColorUtils.transparentize(Looks.colors.accent, dragHandler.active ? 0.75 : 0.94)
        radius: root.radius
        border.width: 1
        border.color: ColorUtils.transparentize(Looks.colors.accent, dragHandler.active ? 0 : 0.5)

        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        // Every edge and corner is a size handle. Nothing is drawn for them -- the
        // cursor over one already says what it does -- and they come before the
        // buttons so that a press on a button is still a press on the button.
        Repeater {
            model: [
                {
                    gripX: -1,
                    gripY: -1
                },
                {
                    gripX: 0,
                    gripY: -1
                },
                {
                    gripX: 1,
                    gripY: -1
                },
                {
                    gripX: -1,
                    gripY: 0
                },
                {
                    gripX: 1,
                    gripY: 0
                },
                {
                    gripX: -1,
                    gripY: 1
                },
                {
                    gripX: 0,
                    gripY: 1
                },
                {
                    gripX: 1,
                    gripY: 1
                }
            ]
            delegate: SizeHandle {
                required property var modelData
                gripX: modelData.gripX
                gripY: modelData.gripY
            }
        }

        RowLayout {
            anchors {
                top: parent.top
                right: parent.right
                margins: 6
            }
            spacing: 4

            WPanelIconButton {
                implicitWidth: 26
                implicitHeight: 26
                iconSize: 14
                iconName: "dismiss"
                onClicked: BoardState.removeCard(root.cardId)
            }
        }
    }

    /// One edge or corner of the card. gripX and gripY say which: -1 is the near
    /// side, 1 the far side, 0 the span between them.
    component SizeHandle: Item {
        id: handle

        required property int gripX
        required property int gripY

        readonly property int reach: Math.round(BoardLooks.unit * 0.7)
        readonly property int shape: {
            if (handle.gripX === 0)
                return Qt.SizeVerCursor;
            if (handle.gripY === 0)
                return Qt.SizeHorCursor;
            return handle.gripX === handle.gripY ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
        }

        x: handle.gripX < 0 ? 0 : (handle.gripX > 0 ? parent.width - handle.width : handle.reach)
        y: handle.gripY < 0 ? 0 : (handle.gripY > 0 ? parent.height - handle.height : handle.reach)
        width: handle.gripX === 0 ? Math.max(0, parent.width - handle.reach * 2) : handle.reach
        height: handle.gripY === 0 ? Math.max(0, parent.height - handle.reach * 2) : handle.reach

        HoverHandler {
            cursorShape: handle.shape
        }

        DragHandler {
            id: handleDrag
            target: null
            cursorShape: handle.shape
            onActiveChanged: {
                if (handleDrag.active) {
                    root.aimAtSize(handle.gripX, handle.gripY, handleDrag.activeTranslation);
                    return;
                }
                if (!root.arrangeable) {
                    root.abandonGesture();
                    return;
                }
                root.settleSize();
            }
            onActiveTranslationChanged: {
                if (handleDrag.active)
                    root.aimAtSize(handle.gripX, handle.gripY, handleDrag.activeTranslation);
            }
        }
    }
}
