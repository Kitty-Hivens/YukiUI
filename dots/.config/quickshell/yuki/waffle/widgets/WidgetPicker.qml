pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks
import qs.waffle.widgets

/**
 * The widgets there are to choose from, shown as themselves rather than as a list
 * of names: what stands here is the card that will stand on the board. One is
 * dragged out of this window and onto the board, which is where it is placed.
 */
BodyRectangle {
    id: root

    /// True while one of the offers is being carried out of the window.
    property bool carrying: false

    // A card carried off the board and over this panel is being given back, and the
    // panel says so before it is let go.
    Rectangle {
        anchors.fill: parent
        visible: BoardState.returning
        color: ColorUtils.transparentize(Looks.colors.accent, 0.88)
        radius: parent.radius
        border.width: 1
        border.color: ColorUtils.transparentize(Looks.colors.accent, 0.4)
        z: 5
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: BoardLooks.padding
        }
        spacing: BoardLooks.gutter

        WText {
            Layout.fillWidth: true
            text: Translation.tr("Widgets").toUpperCase()
            color: BoardLooks.readoutColor
            font.family: BoardLooks.readoutFamily
            font.pixelSize: BoardLooks.readoutSize
            font.letterSpacing: BoardLooks.readoutSpacing
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: BoardLooks.rule
        }

        WFlickable {
            id: offerFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Not scrolling while an offer is being carried: the press belongs to the
            // card. It stays clipped -- the copy on its way to the board is drawn by
            // the window, not by anything in here.
            clip: true
            interactive: !root.carrying
            contentWidth: width
            contentHeight: offerColumn.implicitHeight

            ColumnLayout {
                id: offerColumn
                width: offerFlickable.width
                spacing: BoardLooks.gutter

                Repeater {
                    model: ScriptModel {
                        values: BoardState.unpinnedCards
                    }
                    delegate: PickerSample {
                        required property var modelData
                        cardId: modelData
                    }
                }

                WText {
                    Layout.fillWidth: true
                    Layout.topMargin: BoardLooks.gutter
                    visible: BoardState.unpinnedCards.length === 0
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Every widget is on the board")
                    color: Looks.colors.subfg
                }
            }
        }
    }

    /// One offered widget: the card itself, carried out of the window by its own
    /// surface rather than by a handle.
    component PickerSample: Item {
        id: sample
        required property string cardId

        Layout.fillWidth: true
        implicitHeight: sampleLoader.implicitHeight

        // The card itself stays put and dims; what follows the pointer is drawn by
        // the window, where nothing masks it.
        opacity: sampleDrag.active ? 0.35 : 1

        HoverHandler {
            cursorShape: Qt.OpenHandCursor
        }

        DragHandler {
            id: sampleDrag
            target: null
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: {
                root.carrying = active;
                if (active) {
                    BoardState.carriedOffer = sample.cardId;
                    BoardState.carriedWidth = sample.width;
                    BoardState.carriedHeight = sample.height;
                    sample.reportCarried();
                    sample.aimAtBoard();
                    return;
                }
                sample.dropOnBoard();
                BoardState.carriedOffer = "";
            }
            onActiveTranslationChanged: {
                if (!sampleDrag.active)
                    return;
                sample.reportCarried();
                sample.aimAtBoard();
            }
        }

        /// Where the carried copy sits in the window, so the window can draw it there.
        /// mapToItem already accounts for the drag, so the translation goes onto the
        /// corner the card started from and never onto the mapped point.
        function reportCarried() {
            const corner = sample.mapToItem(null, 0, 0);
            BoardState.carriedX = corner.x + sampleDrag.activeTranslation.x;
            BoardState.carriedY = corner.y + sampleDrag.activeTranslation.y;
        }

        function boardCell() {
            return BoardState.cellAtBoardPoint(BoardState.carriedX + sample.width / 2, BoardState.carriedY + sample.height / 2, sample.cardId, sample.height);
        }

        function aimAtBoard() {
            BoardState.aimDrop(sample.boardCell());
        }

        /// Lands on the cell that was highlighted, rather than working the position
        /// out again: the last movement may have crossed into another cell after the
        /// aim was last taken.
        function dropOnBoard() {
            const aimed = BoardState.aimedCell();
            BoardState.aimDrop(null);
            if (!aimed)
                return;
            BoardState.dropOnBoard(sample.cardId, aimed);
        }

        WidgetCardFor {
            id: sampleLoader
            width: parent.width
            cardId: sample.cardId
            sample: true
        }
    }
}
