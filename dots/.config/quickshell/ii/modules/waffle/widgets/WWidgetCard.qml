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

    // Arranging happens over the card, not inside its heading: picking it up and
    // dropping it somewhere is the whole gesture, and the readings stay put.
    readonly property bool arrangeable: root.unpinnable && BoardState.editing

    z: dragHandler.active ? 10 : 0
    transform: Translate {
        x: dragHandler.active ? dragHandler.activeTranslation.x : 0
        y: dragHandler.active ? dragHandler.activeTranslation.y : 0
    }

    DragHandler {
        id: dragHandler
        enabled: root.arrangeable
        target: null
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            if (!active)
                root.dropWhereItLies();
        }
    }

    /// The card under this one's middle is the place it was dropped on.
    function dropWhereItLies() {
        const middleX = root.x + dragHandler.activeTranslation.x + root.width / 2;
        const middleY = root.y + dragHandler.activeTranslation.y + root.height / 2;
        for (const sibling of root.parent.children) {
            if (sibling === root || sibling.cardId === undefined || !sibling.visible)
                continue;
            if (middleX < sibling.x || middleX > sibling.x + sibling.width)
                continue;
            if (middleY < sibling.y || middleY > sibling.y + sibling.height)
                continue;
            BoardState.moveCardTo(root.cardId, BoardState.pinnedCards.indexOf(sibling.cardId));
            return;
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.arrangeable
        color: ColorUtils.transparentize(Looks.colors.accent, dragHandler.active ? 0.75 : 0.94)
        radius: root.radius
        border.width: 1
        border.color: ColorUtils.transparentize(Looks.colors.accent, dragHandler.active ? 0 : 0.5)

        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        WPanelIconButton {
            anchors {
                top: parent.top
                right: parent.right
                margins: 6
            }
            implicitWidth: 26
            implicitHeight: 26
            iconSize: 14
            iconName: "dismiss"
            onClicked: BoardState.removeCard(root.cardId)
        }
    }
}
