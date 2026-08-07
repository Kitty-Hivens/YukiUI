pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

// One card on the board: a heading set in caps, a reading beside it, a rule under
// both, and whatever the card puts below that. Corner marks stand in for a border.
Rectangle {
    id: root

    required property string cardId
    property string title: ""
    property string iconName: "apps"
    property color foregroundColor: Looks.colors.fg
    /// Small monospaced text along the heading -- a reading, not a label.
    property string readout: ""
    // A card that has somewhere to send you says so along its bottom edge.
    property string actionText: ""
    property bool unpinnable: true
    signal actionTriggered
    default property alias cardContent: contentArea.data

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    /// The least the card can be drawn in. Its actual height is however many rows
    /// it was dragged to cover, which the board sets.
    readonly property int naturalHeight: contentColumn.implicitHeight + BoardLooks.cardPadding * 2
    implicitHeight: root.naturalHeight
    height: root.naturalHeight
    onNaturalHeightChanged: root.parent?.relayoutLater?.()

    Behavior on x {
        enabled: !dragHandler.active
        animation: Looks.transition.move.createObject(this)
    }
    Behavior on y {
        enabled: !dragHandler.active
        animation: Looks.transition.move.createObject(this)
    }

    color: Looks.colors.bg1
    radius: Looks.radius.medium

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
    /// A card shown as a sample in the picker is not on the board: it carries no
    /// arranging controls and its own contents do not take the pointer.
    property bool sample: false
    readonly property bool arrangeable: root.unpinnable && BoardState.editing && !root.sample

    z: dragHandler.active ? 10 : 0
    /// While it is being carried the card is drawn by the window rather than here,
    /// so it is not cut off at the edge of the panel it is leaving.
    opacity: dragHandler.active ? 0 : 1

    function reportCarried() {
        const board = root.parent;
        const corner = board.mapToItem(null, root.x + dragHandler.activeTranslation.x, root.y + dragHandler.activeTranslation.y);
        BoardState.carriedX = corner.x;
        BoardState.carriedY = corner.y;
    }

    DragHandler {
        id: dragHandler
        enabled: root.arrangeable && !root.sample
        target: null
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            const board = root.parent;
            if (active) {
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

    /// Where the card has been carried to, in the coordinates the board shares with
    /// the picker's window.
    function carriedCentre() {
        const board = root.parent;
        const carriedX = root.x + dragHandler.activeTranslation.x + root.width / 2;
        const carriedY = root.y + dragHandler.activeTranslation.y + root.height / 2;
        return board.mapToItem(null, carriedX, carriedY);
    }

    /// The cell the card is currently over, marked out on the board so the landing
    /// place is visible before it is let go. Carried onto the picker instead, it is
    /// being given back, and no cell is marked.
    function aimAtCell() {
        const board = root.parent;
        const centre = root.carriedCentre();
        BoardState.returning = BoardState.overPicker(centre.x, centre.y);
        if (BoardState.returning) {
            board.dropColumn = -1;
            return;
        }
        const carriedX = root.x + dragHandler.activeTranslation.x;
        const carriedY = root.y + dragHandler.activeTranslation.y;
        const span = Math.min(BoardState.spanOf(root.cardId), board.cells);
        const cell = board.cellAt(carriedX, carriedY, span);
        board.dropSpan = span;
        board.dropRows = board.rowsFor(root);
        board.dropColumn = cell.column;
        board.dropRow = cell.row;
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

        // The corner is the size: dragged out, the card covers whatever rectangle of
        // cells it is pulled over, down to the room its contents need.
        Item {
            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            implicitWidth: Math.round(BoardLooks.unit * 1.2)
            implicitHeight: Math.round(BoardLooks.unit * 1.2)

            WCornerMarks {
                anchors.fill: parent
                anchors.margins: 2
                corners: ["bottomRight"]
                length: Math.round(BoardLooks.unit * 0.8)
                weight: 2
                color: gripHover.hovered || gripDrag.active ? Looks.colors.accent : BoardLooks.cornerColor
            }

            HoverHandler {
                id: gripHover
                cursorShape: Qt.SizeFDiagCursor
            }

            DragHandler {
                id: gripDrag
                target: null
                cursorShape: Qt.SizeFDiagCursor
                onActiveChanged: {
                    if (gripDrag.active) {
                        root.aimAtSize();
                        return;
                    }
                    root.settleSize();
                }
                onActiveTranslationChanged: {
                    if (gripDrag.active)
                        root.aimAtSize();
                }
            }
        }
    }

    /// The rectangle of cells the corner has been pulled over, held inside the board
    /// and never smaller than the card's own contents.
    function sizeUnderGrip() {
        const board = root.parent;
        const entry = board.entryFor(root.cardId);
        if (!entry)
            return null;
        const right = root.x + root.width + gripDrag.activeTranslation.x;
        const bottom = root.y + root.height + gripDrag.activeTranslation.y;
        const overSegments = (right - board.cellX(entry.column) + board.gutter) / board.pitch;
        const overRows = (bottom - entry.row * board.rowHeight + board.gutter) / board.rowHeight;
        return ({
                column: entry.column,
                row: entry.row,
                // A column is the narrowest a card is drawn in; wider goes by segments,
                // so a card and a half across is a size like any other.
                span: Math.max(BoardLooks.segments, Math.min(Math.round(overSegments), board.cells - entry.column)),
                rows: Math.max(board.minRowsFor(root), Math.round(overRows))
            });
    }

    function aimAtSize() {
        const board = root.parent;
        const size = root.sizeUnderGrip();
        if (!size)
            return;
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
        if (!size)
            return;
        // A gesture that ended where it started is not a resize, and writing it back
        // would put every card's current size into the configuration for nothing.
        const entry = board.entryFor(root.cardId);
        if (entry && entry.span === size.span && entry.rows === size.rows)
            return;
        BoardState.setSize(root.cardId, size.span, size.rows);
        board.placeCard(root.cardId, size.column, size.row, size.span, size.rows);
    }
}
