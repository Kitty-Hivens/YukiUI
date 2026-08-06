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

WBarAttachedPanelContent {
    id: root

    revealFromSides: true
    revealFromLeft: true

    readonly property list<string> cards: Config.options.waffles.widgets.cards

    contentItem: WPane {
        contentItem: BodyRectangle {
            implicitWidth: 496
            implicitHeight: 800

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    WPanelIconButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        iconSize: 16
                        iconName: "settings"
                        onClicked: {
                            GlobalStates.widgetsOpen = false;
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("appearanceSettings.qml")]);
                        }
                    }

                    WUserAvatar {
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
                    contentHeight: boardColumn.implicitHeight

                    ColumnLayout {
                        id: boardColumn
                        width: boardFlickable.width
                        spacing: 12

                        Repeater {
                            model: ScriptModel {
                                values: root.cards
                            }
                            delegate: WidgetCardChooser {}
                        }

                        WText {
                            Layout.fillWidth: true
                            Layout.topMargin: 20
                            visible: root.cards.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("No widgets are pinned")
                            color: Looks.colors.subfg
                        }

                        FeedSection {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                        }
                    }
                }
            }
        }
    }
}
