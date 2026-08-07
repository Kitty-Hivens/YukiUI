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
import qs.modules.waffle.widgets.cards

// A board of cards, as wide as it was last dragged to be.
WBarAttachedPanelContent {
    id: root

    revealFromSides: true
    revealFromLeft: true

    readonly property list<string> cards: Config.options.waffles.widgets.cards
    readonly property int columnWidth: BoardLooks.columnWidth
    readonly property int columnSpacing: BoardLooks.gutter
    readonly property int boardPadding: BoardLooks.padding

    function widthForColumns(columns) {
        return BoardLooks.widthForColumns(columns);
    }

    /// The width that was asked for, held inside what the screen allows.
    readonly property int askedWidth: {
        const asked = BoardState.width > 0 ? BoardState.width : root.widthForColumns(2);
        return Math.max(root.minBoardWidth, Math.min(asked, root.maxBoardWidth));
    }

    readonly property int screenWidth: QsWindow.window?.screen?.width ?? 1920
    readonly property int maxWidth: Math.min(root.widthForColumns(4) + root.visualMargin * 2, root.screenWidth)
    readonly property int minBoardWidth: root.widthForColumns(1)
    readonly property int maxBoardWidth: Math.min(root.widthForColumns(4), root.maxWidth - root.visualMargin * 2)

    /// However many columns fit in the width the board was left at, which is the
    /// count the state works out; the screen's limit is this panel's to tell.
    readonly property int fittingColumns: BoardState.columns
    readonly property int columnCeiling: BoardState.columnsFor(root.maxBoardWidth)
    onColumnCeilingChanged: BoardState.columnCeiling = root.columnCeiling
    Component.onCompleted: BoardState.columnCeiling = root.columnCeiling

    readonly property string greeting: {
        const hour = DateTime.clock.date.getHours();
        if (hour < 5)
            return Translation.tr("Good night");
        if (hour < 12)
            return Translation.tr("Good morning");
        if (hour < 18)
            return Translation.tr("Good afternoon");
        return Translation.tr("Good evening");
    }

    contentItem: WPane {
        id: boardPane

        contentItem: BodyRectangle {
            id: paneBody

            readonly property int roomForBoard: (root.QsWindow.window?.height ?? 1080) - root.visualMargin * 2

            implicitWidth: root.widthForColumns(root.fittingColumns)
            implicitHeight: Config.options.waffles.widgets.fullHeight ? roomForBoard : Math.min(Config.options.waffles.widgets.height, roomForBoard)

            // The panel beside this one is placed from these, so they are reported as
            // the pane measures -- border included -- rather than as the body alone.
            function reportGeometry() {
                BoardState.boardWidth = boardPane.width + root.visualMargin;
                // The body rather than the pane: the panel beside this one draws its
                // own border around a body of the same height.
                BoardState.boardHeight = paneBody.height;
                BoardState.boardTop = boardPane.mapToItem(null, 0, 0).y;
            }
            onImplicitWidthChanged: reportSoon.restart()
            onImplicitHeightChanged: reportSoon.restart()
            Component.onCompleted: reportSoon.restart()

            Timer {
                id: reportSoon
                interval: 0
                onTriggered: paneBody.reportGeometry()
            }

            Connections {
                target: boardPane
                function onXChanged() {
                    reportSoon.restart();
                }
                function onYChanged() {
                    reportSoon.restart();
                }
            }

            // Pinned to the corner of the panel rather than sitting in the heading row.
            RowLayout {
                z: 5
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: root.boardPadding
                }
                spacing: 6

                HeaderButton {
                    iconName: BoardState.wide ? "arrow-minimize" : "arrow-expand"
                    onClicked: BoardState.toggleWide()
                }
                HeaderButton {
                    iconName: BoardState.editing ? "checkmark" : "edit"
                    checked: BoardState.editing
                    onClicked: BoardState.editing = !BoardState.editing
                }
            }

            // The right edge is a handle: the board is as wide as it is dragged to be.
            Rectangle {
                z: 6
                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                width: Math.round(BoardLooks.unit * 0.4)
                color: edgeHover.hovered || edgeDrag.active ? Looks.colors.accent : "transparent"

                Behavior on color {
                    animation: Looks.transition.color.createObject(this)
                }

                HoverHandler {
                    id: edgeHover
                    cursorShape: Qt.SizeHorCursor
                }
                DragHandler {
                    id: edgeDrag
                    target: null
                    cursorShape: Qt.SizeHorCursor
                    yAxis.enabled: false
                    // From the width that was asked for rather than the one it snapped
                    // to, so the pixels inside the last column survive to the next drag.
                    property int widthAtStart: 0
                    onActiveChanged: {
                        if (active)
                            widthAtStart = root.askedWidth;
                    }
                    onActiveTranslationChanged: {
                        if (!edgeDrag.active)
                            return;
                        const wanted = edgeDrag.widthAtStart + edgeDrag.activeTranslation.x;
                        BoardState.width = Math.max(root.minBoardWidth, Math.min(wanted, root.maxBoardWidth));
                    }
                }
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: root.boardPadding
                }
                spacing: Math.round(BoardLooks.unit * 1.2)

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.rightMargin: Math.round(BoardLooks.unit * 5)
                    spacing: 2

                    WText {
                        text: root.greeting
                        font.pixelSize: Looks.font.pixelSize.xlarger
                        font.weight: Looks.font.weight.strong
                    }
                    // The date and the clock read as an instrument's line, not a subtitle.
                    WText {
                        text: Qt.locale().toString(DateTime.clock.date, "ddd dd MMM yyyy").toUpperCase() + "  ·  " + DateTime.time
                        color: BoardLooks.readoutColor
                        font.family: BoardLooks.readoutFamily
                        font.pixelSize: BoardLooks.readoutSize
                        font.letterSpacing: BoardLooks.readoutSpacing
                    }
                }

                StyledFlickable {
                    id: boardFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // A press on a card while arranging is a grab of that card, not of
                    // the list it is in.
                    interactive: !BoardState.editing
                    clip: true
                    contentWidth: width
                    contentHeight: boardBody.implicitHeight

                    Item {
                        id: boardBody
                        width: boardFlickable.width
                        implicitHeight: cardArea.implicitHeight + (extras.implicitHeight > 0 ? extras.implicitHeight + root.columnSpacing : 0)

                        WidgetBoardArea {
                            id: cardArea
                            width: parent.width
                            columns: root.fittingColumns
                            columnWidth: root.columnWidth
                            gutter: root.columnSpacing
                        }

                        ColumnLayout {
                            id: extras
                            anchors {
                                top: cardArea.bottom
                                topMargin: root.columnSpacing
                                left: parent.left
                                right: parent.right
                            }
                            spacing: root.columnSpacing

                            NewsCard {
                                Layout.fillWidth: true
                            }

                            WText {
                                Layout.fillWidth: true
                                visible: root.cards.length === 0 && !BoardState.editing
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("No widgets are pinned")
                                color: Looks.colors.subfg
                            }
                        }
                    }
                }
            }
        }
    }

    component HeaderButton: WPanelIconButton {
        implicitWidth: Math.round(BoardLooks.controlSize * 1.4)
        implicitHeight: Math.round(BoardLooks.controlSize * 1.4)
        iconSize: Math.round(BoardLooks.controlSize * 0.7)
    }
}
