pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

// Adding a widget is its own window over the board, the way the board this borrows
// from opens a list rather than growing a shelf along its bottom edge.
Popup {
    id: root

    modal: true
    dim: true
    padding: 0
    anchors.centerIn: Overlay.overlay

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
        }
    }

    background: Rectangle {
        color: Looks.colors.bg1Base
        radius: Looks.radius.large
        border.width: 1
        border.color: Looks.colors.bg2Border
    }

    Overlay.modal: Rectangle {
        color: ColorUtils.transparentize("#000000", 0.5)
    }

    contentItem: ColumnLayout {
        implicitWidth: Math.round(BoardLooks.unit * 24)
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: BoardLooks.padding
            Layout.bottomMargin: Math.round(BoardLooks.unit * 0.5)
            spacing: 2

            WText {
                text: Translation.tr("Add a widget")
                font.pixelSize: Looks.font.pixelSize.larger
                font.weight: Looks.font.weight.strong
            }
            WText {
                text: Translation.tr("%1 available").arg(BoardState.unpinnedCards.length).toUpperCase()
                color: BoardLooks.readoutColor
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Math.round(BoardLooks.unit * 0.5)
            spacing: 2

            WText {
                Layout.fillWidth: true
                Layout.margins: Math.round(BoardLooks.unit * 0.5)
                visible: BoardState.unpinnedCards.length === 0
                text: Translation.tr("Everything is already on the board")
                color: Looks.colors.subfg
            }

            Repeater {
                model: ScriptModel {
                    values: BoardState.unpinnedCards
                }
                delegate: WButton {
                    id: offer
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Math.round(BoardLooks.unit * 2.6)
                    horizontalAlignment: Text.AlignLeft
                    icon.name: BoardState.iconOf(offer.modelData)
                    text: BoardState.nameOf(offer.modelData)
                    onClicked: {
                        BoardState.addCard(offer.modelData);
                        if (BoardState.unpinnedCards.length === 0)
                            root.close();
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: BoardLooks.rule
        }

        WTextButton {
            Layout.alignment: Qt.AlignRight
            Layout.margins: Math.round(BoardLooks.unit * 0.5)
            text: Translation.tr("Done")
            onClicked: root.close()
        }
    }
}
