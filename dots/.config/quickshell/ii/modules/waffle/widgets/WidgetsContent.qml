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

// A board of cards, two columns wide. The board this sits beside gives a third of
// itself to cards and the rest to a feed of stories; there is no such feed here, so
// the cards get the room and the news, when it is switched on, is a card among them.
WBarAttachedPanelContent {
    id: root

    revealFromSides: true
    revealFromLeft: true

    readonly property list<string> cards: Config.options.waffles.widgets.cards
    readonly property int columnWidth: 336
    readonly property int columnSpacing: 16

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
            implicitWidth: root.columnWidth * 2 + root.columnSpacing + 24 * 2
            implicitHeight: 860

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 24
                }
                spacing: 18

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
                    clip: true
                    contentWidth: width
                    contentHeight: boardGrid.implicitHeight

                    GridLayout {
                        id: boardGrid
                        width: boardFlickable.width
                        columns: 2
                        columnSpacing: root.columnSpacing
                        rowSpacing: root.columnSpacing

                        Repeater {
                            model: ScriptModel {
                                values: root.cards
                            }
                            delegate: WidgetCardChooser {}
                        }

                        NewsCard {
                            Layout.columnSpan: 2
                        }

                        WText {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            visible: root.cards.length === 0 && !BoardState.editing
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("No widgets are pinned")
                            color: Looks.colors.subfg
                        }

                        // What is not on the board, offered while it is being arranged.
                        ColumnLayout {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            visible: BoardState.editing
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: BoardLooks.rule
                            }

                            WText {
                                text: Translation.tr("Add a widget").toUpperCase()
                                color: BoardLooks.readoutColor
                                font.family: BoardLooks.readoutFamily
                                font.pixelSize: BoardLooks.readoutSize
                                font.letterSpacing: BoardLooks.readoutSpacing
                            }

                            WText {
                                Layout.fillWidth: true
                                visible: BoardState.unpinnedCards.length === 0
                                text: Translation.tr("Everything is already on the board")
                                color: Looks.colors.subfg
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: ScriptModel {
                                        values: BoardState.unpinnedCards
                                    }
                                    delegate: WBorderedButton {
                                        id: addButton
                                        required property var modelData
                                        implicitHeight: 34
                                        icon.name: BoardState.iconOf(addButton.modelData)
                                        text: BoardState.nameOf(addButton.modelData)
                                        onClicked: BoardState.addCard(addButton.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component HeaderButton: WPanelIconButton {
        implicitWidth: 32
        implicitHeight: 32
        iconSize: 16
    }
}
