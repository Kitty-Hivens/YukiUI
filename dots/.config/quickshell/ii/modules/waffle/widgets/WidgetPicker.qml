pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

/**
 * The widgets there are to choose from, shown as themselves rather than as a list
 * of names: what stands here is the card that will stand on the board. One is
 * dragged out of this window and onto the board, which is where it is placed.
 */
BodyRectangle {
    id: root

    /// True while one of the offers is being carried out of the window.
    property bool carrying: false

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

        StyledFlickable {
            id: offerFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Neither clipped nor scrolling while an offer is being carried: the card
            // has to be visible on its way to the board, and the press belongs to it.
            clip: !root.carrying
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

        z: sampleDrag.active ? 10 : 0
        transform: Translate {
            x: sampleDrag.active ? sampleDrag.activeTranslation.x : 0
            y: sampleDrag.active ? sampleDrag.activeTranslation.y : 0
        }

        opacity: sampleDrag.active ? 0.85 : 1

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
                    sample.aimAtBoard();
                    return;
                }
                sample.dropOnBoard();
            }
            onActiveTranslationChanged: {
                if (sampleDrag.active)
                    sample.aimAtBoard();
            }
        }

        /// The board is a window of its own, so the pointer is followed through the
        /// picker window's own offset rather than through a shared parent.
        /// mapToItem already accounts for the transform the drag applies, so the
        /// translation must not be added a second time.
        function boardCell() {
            const inWindow = sample.mapToItem(null, sample.width / 2, sample.height / 2);
            return BoardState.cellAtBoardPoint(inWindow.x + BoardState.pickerLeft, inWindow.y, sample.cardId, sample.height);
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
