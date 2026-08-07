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

// A board of cards. The board this sits beside gives a third of itself to cards and
// the rest to a feed of stories; there is no such feed here, so the cards get the
// room and the news, when it is switched on, is a card among them.
WBarAttachedPanelContent {
    id: root

    revealFromSides: true
    revealFromLeft: true

    readonly property list<string> cards: Config.options.waffles.widgets.cards
    readonly property int columnWidth: BoardLooks.columnWidth
    readonly property int columnSpacing: BoardLooks.gutter
    readonly property int boardPadding: BoardLooks.padding

    function widthForColumns(columns) {
        return root.columnWidth * columns + root.columnSpacing * (columns - 1) + root.boardPadding * 2;
    }

    /// The window is held at the widest the board can be. Resizing a layer surface
    /// makes the compositor drop the focus grab and blanks the surface while it
    /// settles, and neither is worth an animation.
    readonly property int screenWidth: QsWindow.window?.screen?.width ?? 1920
    readonly property int maxWidth: Math.min(root.widthForColumns(3) + root.visualMargin * 2, root.screenWidth)

    /// Columns asked for, minus the ones the screen has no room for.
    readonly property int fittingColumns: {
        const room = root.maxWidth - root.visualMargin * 2 - root.boardPadding * 2;
        const fits = Math.floor((room + root.columnSpacing) / (root.columnWidth + root.columnSpacing));
        return Math.max(1, Math.min(BoardState.columns, fits));
    }

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
        contentItem: BodyRectangle {
            // Measured from the window rather than from the panel: the panel's height
            // comes from this, and reading it back here would chase its own tail.
            readonly property int roomForBoard: (root.QsWindow.window?.height ?? 1080) - root.visualMargin * 2

            implicitWidth: root.widthForColumns(root.fittingColumns)
            implicitHeight: Config.options.waffles.widgets.fullHeight ? roomForBoard : Math.min(Config.options.waffles.widgets.height, roomForBoard)

            Behavior on implicitWidth {
                animation: Looks.transition.resize.createObject(this)
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: root.boardPadding
                }
                spacing: Math.round(BoardLooks.unit * 1.2)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
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

                    HeaderButton {
                        iconName: BoardState.wide ? "arrow-minimize" : "arrow-expand"
                        onClicked: BoardState.wide = !BoardState.wide
                    }
                    HeaderButton {
                        iconName: "add"
                        onClicked: addDialog.open()
                    }
                    HeaderButton {
                        iconName: BoardState.editing ? "checkmark" : "edit"
                        checked: BoardState.editing
                        onClicked: BoardState.editing = !BoardState.editing
                    }
                    WUserAvatar {
                        Layout.leftMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        sourceSize: Qt.size(32, 32)
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

    AddWidgetDialog {
        id: addDialog
    }

    component HeaderButton: WPanelIconButton {
        implicitWidth: Math.round(BoardLooks.controlSize * 1.4)
        implicitHeight: Math.round(BoardLooks.controlSize * 1.4)
        iconSize: Math.round(BoardLooks.controlSize * 0.7)
    }
}
