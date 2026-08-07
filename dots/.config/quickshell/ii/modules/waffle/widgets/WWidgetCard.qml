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
    implicitHeight: contentColumn.implicitHeight + BoardLooks.cardPadding * 2
    height: implicitHeight
    onHeightChanged: root.parent?.relayout?.()

    Behavior on x {
        enabled: !dragHandler.active
        animation: Looks.transition.move.createObject(this)
    }
    Behavior on y {
        enabled: !dragHandler.active
        animation: Looks.transition.move.createObject(this)
    }

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
            margins: BoardLooks.cardPadding
        }
        spacing: Math.round(BoardLooks.unit * 0.66)

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
            if (active) {
                root.parent.carried = root;
                root.aimAtCell();
                return;
            }
            root.parent.dropCarried();
            root.parent.dropColumn = -1;
            root.parent.carried = null;
        }
        onCentroidChanged: {
            if (dragHandler.active)
                root.aimAtCell();
        }
        onActiveTranslationChanged: {
            if (dragHandler.active)
                root.aimAtCell();
        }
    }

    /// The cell the card is currently over, marked out on the board so the landing
    /// place is visible before it is let go.
    function aimAtCell() {
        const board = root.parent;
        const carriedX = root.x + dragHandler.activeTranslation.x;
        const carriedY = root.y + dragHandler.activeTranslation.y;
        const span = Math.min(BoardState.spanOf(root.cardId), board.columns);
        const cell = board.cellAt(carriedX, carriedY, span);
        board.dropSpan = span;
        board.dropRows = board.rowsFor(root);
        board.dropColumn = cell.column;
        board.dropRow = cell.row;
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

        RowLayout {
            anchors {
                top: parent.top
                right: parent.right
                margins: 6
            }
            spacing: 4

            WPanelIconButton {
                implicitWidth: 26
                implicitHeight: 26
                iconSize: 14
                iconName: BoardState.spanOf(root.cardId) === 2 ? "arrow-minimize" : "arrow-expand"
                onClicked: BoardState.toggleSpan(root.cardId)
            }

            WPanelIconButton {
                implicitWidth: 26
                implicitHeight: 26
                iconSize: 14
                iconName: "dismiss"
                onClicked: BoardState.removeCard(root.cardId)
            }
        }
    }
}
