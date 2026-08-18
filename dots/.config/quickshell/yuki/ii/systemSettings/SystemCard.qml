import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

Rectangle {
    id: root
    property string title: ""
    property string icon: ""
    property string subtitle: ""
    default property alias cardData: cardContent.data

    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    radius: Appearance.rounding.normal
    implicitHeight: cardColumn.implicitHeight + cardColumn.anchors.margins * 2

    ColumnLayout {
        id: cardColumn
        // Bound to the bottom as well, so a card the layout has made shorter
        // than its content passes that shortage on. Without it the column kept
        // its full height and simply drew past the card it lives in.
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            margins: 16
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.title.length > 0

            MaterialSymbol {
                visible: root.icon.length > 0
                text: root.icon
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnLayer2
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Takes what the title row leaves, so content that scrolls gets a
        // height to scroll within rather than one it computed from itself.
        ColumnLayout {
            id: cardContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
        }
    }
}
