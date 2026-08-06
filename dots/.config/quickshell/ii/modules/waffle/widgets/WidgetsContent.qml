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
import qs.modules.waffle.widgets.cards

// The board is two columns: the cards that were pinned, and the stories beside
// them, under a greeting that carries the date.
WBarAttachedPanelContent {
    id: root

    revealFromSides: true
    revealFromLeft: true

    readonly property list<string> cards: Config.options.waffles.widgets.cards
    readonly property int cardColumnWidth: 320
    readonly property int storyColumnWidth: 340

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
            implicitWidth: root.cardColumnWidth + root.storyColumnWidth * 2 + 16 + 24 * 3
            implicitHeight: 900

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 24
                }
                spacing: 20

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        WText {
                            text: Qt.locale().toString(DateTime.clock.date, "d MMMM")
                            color: Looks.colors.subfg
                        }
                        WText {
                            text: root.greeting
                            font.pixelSize: Looks.font.pixelSize.xlarger
                            font.weight: Looks.font.weight.strong
                        }
                    }

                    HeaderButton {
                        iconName: "arrow-clockwise"
                        onClicked: {
                            Weather.getData();
                            NewsFeed.refresh();
                        }
                    }
                    HeaderButton {
                        iconName: "settings"
                        onClicked: {
                            GlobalStates.widgetsOpen = false;
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("appearanceSettings.qml")]);
                        }
                    }
                    WUserAvatar {
                        Layout.leftMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        sourceSize: Qt.size(32, 32)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 24

                    // Pinned cards
                    ColumnLayout {
                        Layout.preferredWidth: root.cardColumnWidth
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            WText {
                                Layout.fillWidth: true
                                text: Translation.tr("Widgets")
                                font.weight: Looks.font.weight.strong
                            }
                            HeaderButton {
                                iconName: "add"
                                implicitWidth: 28
                                implicitHeight: 28
                            }
                        }

                        StyledFlickable {
                            id: cardFlickable
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: cardColumn.implicitHeight

                            ColumnLayout {
                                id: cardColumn
                                width: cardFlickable.width
                                spacing: 12

                                Repeater {
                                    model: ScriptModel {
                                        values: root.cards
                                    }
                                    delegate: WidgetCardChooser {}
                                }

                                WText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 12
                                    visible: root.cards.length === 0
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("No widgets are pinned")
                                    color: Looks.colors.subfg
                                }
                            }
                        }
                    }

                    // Stories
                    FeedSection {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columnWidth: root.storyColumnWidth
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
