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
    implicitHeight: contentColumn.implicitHeight + 32

    color: Looks.colors.bg1
    radius: Looks.radius.medium

    WCornerMarks {
        anchors.fill: parent
        anchors.margins: 6
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            // Held at the height of the arrange controls whether they are showing or
            // not, so entering and leaving arranging does not resize every card.
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
                visible: root.readout.length > 0
                text: root.readout
                color: ColorUtils.transparentize(root.foregroundColor, 0.45)
                font.family: BoardLooks.readoutFamily
                font.pixelSize: BoardLooks.readoutSize
                font.letterSpacing: BoardLooks.readoutSpacing
            }

            // While the board is being arranged, the heading carries the controls for
            // arranging this card instead of a menu holding one item.
            CardButton {
                visible: root.unpinnable && BoardState.editing
                enabled: BoardState.canMove(root.cardId, -1)
                iconName: "arrow-left"
                onClicked: BoardState.moveCard(root.cardId, -1)
            }
            CardButton {
                visible: root.unpinnable && BoardState.editing
                enabled: BoardState.canMove(root.cardId, 1)
                iconName: "arrow-right"
                onClicked: BoardState.moveCard(root.cardId, 1)
            }
            CardButton {
                visible: root.unpinnable && BoardState.editing
                iconName: "dismiss"
                onClicked: BoardState.removeCard(root.cardId)
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

    component CardButton: WPanelIconButton {
        implicitWidth: 24
        implicitHeight: 24
        iconSize: 14
        Layout.alignment: Qt.AlignVCenter
    }
}
