pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * What a page says when there is nothing on it: the one thing that is so, what
 * to do about it, and the button that does it.
 *
 * It takes the height the rest of the page leaves rather than sitting as a strip
 * under the heading, because a page with nothing on it has nothing else to fill
 * itself with, and a line stranded at the top reads as a page still loading.
 *
 * This is for a page with nothing on it. A section with nothing in it, on a page
 * that has other things, says so in a [PageNote] and stays the size of a line.
 */
SystemCard {
    id: root

    /** The large glyph, which is not the small one a card puts beside its title. */
    required property string symbol
    required property string heading
    property string message: ""
    property string actionIcon: ""
    property string actionText: ""
    /** What the rest of the page leaves for it, in pixels. */
    property real roomLeft: 0

    signal actionClicked()

    Layout.fillWidth: true
    Layout.topMargin: 8
    Layout.preferredHeight: Math.max(260, root.roomLeft)

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 6

        Item { Layout.fillHeight: true }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.symbol
            iconSize: 56
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.heading
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.message.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.message
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            visible: root.actionText.length > 0
            materialIcon: root.actionIcon
            mainText: root.actionText
            onClicked: root.actionClicked()
        }

        Item { Layout.fillHeight: true }
    }
}
