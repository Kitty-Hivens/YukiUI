pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

// One card on the board: a header with an icon, a name and a menu, and whatever
// the card itself puts below it.
Rectangle {
    id: root

    required property string cardId
    property string title: ""
    property string iconName: "apps"
    // Cards carry their own colour where the original does -- the weather one is a
    // block of colour there, the rest sit on the board's own surface.
    property color foregroundColor: Looks.colors.fg
    // A card that has somewhere to send you says so along its bottom edge, the one
    // part of the original's card that is worth keeping wholesale.
    property string actionText: ""
    property bool unpinnable: true
    signal actionTriggered
    default property alias cardContent: contentArea.data

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    implicitHeight: contentColumn.implicitHeight + 32

    color: Looks.colors.bg1
    radius: Looks.radius.large
    border.width: 1
    border.color: Looks.colors.bg2Border

    ColumnLayout {
        id: contentColumn
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            FluentIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: root.iconName
                implicitSize: 18
                monochrome: true
                color: root.foregroundColor
            }

            WText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.title
                elide: Text.ElideRight
                color: root.foregroundColor
                font.pixelSize: Looks.font.pixelSize.large
                font.weight: Looks.font.weight.strong
            }

            WPanelIconButton {
                id: menuButton
                visible: root.unpinnable
                implicitWidth: 28
                implicitHeight: 28
                iconSize: 16
                iconName: "more-horizontal"
                // Held lit for as long as its menu is: the pointer moves onto the menu,
                // which takes the hover with it and left the button looking untouched.
                checked: cardMenu.visible
                onClicked: cardMenu.popup()

                WMenu {
                    id: cardMenu
                    downDirection: true

                    WMenuItem {
                        icon.name: "pin-off"
                        text: Translation.tr("Unpin widget")
                        onTriggered: {
                            Config.options.waffles.widgets.cards = Config.options.waffles.widgets.cards.filter(card => card !== root.cardId);
                        }
                    }
                }
            }
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
            implicitHeight: 30
            text: root.actionText
            onClicked: root.actionTriggered()
        }
    }
}
