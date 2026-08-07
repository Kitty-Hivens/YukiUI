pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.waffle.widgets

/**
 * Where the cards are placed.
 *
 * A layout owns the positions of what is inside it, which means nothing can be
 * picked up, carried over its neighbours and dropped between two of them. So the
 * cards are placed here instead: each goes into the column that currently ends
 * highest, in the order the configuration lists them, and a card being carried is
 * left out of that pass so the others close over the space it left.
 */
Item {
    id: root

    required property int columns
    required property int columnWidth
    required property int gutter

    /// The card currently being carried, if any. It keeps its place in the order
    /// but not in the packing.
    property Item carried: null

    implicitHeight: root.packedHeight
    property real packedHeight: 0

    function cardItems() {
        const byId = ({});
        for (const child of root.children) {
            if (child.cardId !== undefined && child.visible)
                byId[child.cardId] = child;
        }
        return BoardState.pinnedCards.map(id => byId[id]).filter(item => item !== undefined);
    }

    function relayout() {
        const columnEnds = new Array(root.columns).fill(0);
        const spanWidth = column => root.columnWidth * column + root.gutter * (column - 1);

        for (const item of root.cardItems()) {
            const span = Math.min(BoardState.spanOf(item.cardId), root.columns);
            item.width = spanWidth(span);

            if (item === root.carried)
                continue;

            // The run of columns of the right length whose tallest end is lowest.
            var bestStart = 0;
            var bestTop = Infinity;
            for (var start = 0; start + span <= root.columns; start++) {
                var top = 0;
                for (var offset = 0; offset < span; offset++) top = Math.max(top, columnEnds[start + offset]);
                if (top < bestTop) {
                    bestTop = top;
                    bestStart = start;
                }
            }

            item.x = bestStart * (root.columnWidth + root.gutter);
            item.y = bestTop;
            for (var filled = 0; filled < span; filled++) columnEnds[bestStart + filled] = bestTop + item.height + root.gutter;
        }

        root.packedHeight = Math.max(0, Math.max.apply(null, columnEnds) - root.gutter);
    }

    /// Where a card would land if it were let go over this point.
    function indexAt(pointX, pointY) {
        const items = root.cardItems();
        for (var i = 0; i < items.length; i++) {
            const item = items[i];
            if (item === root.carried)
                continue;
            if (pointX < item.x || pointX > item.x + item.width)
                continue;
            if (pointY < item.y || pointY > item.y + item.height)
                continue;
            return BoardState.pinnedCards.indexOf(item.cardId);
        }
        return -1;
    }

    onWidthChanged: root.relayout()
    onColumnsChanged: root.relayout()
    onCarriedChanged: root.relayout()

    Connections {
        target: BoardState
        function onPinnedCardsChanged() {
            Qt.callLater(root.relayout);
        }
    }

    Repeater {
        model: ScriptModel {
            values: BoardState.pinnedCards
        }
        delegate: WidgetCardChooser {}
        onItemAdded: Qt.callLater(root.relayout)
        onItemRemoved: Qt.callLater(root.relayout)
    }
}
