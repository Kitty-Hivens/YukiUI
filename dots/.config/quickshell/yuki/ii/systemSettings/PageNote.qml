import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * What a card says when it has nothing to list. Kept as a line of text rather
 * than an empty card, so the section still says what it is about.
 */
StyledText {
    Layout.fillWidth: true
    Layout.topMargin: 2
    Layout.bottomMargin: 2
    wrapMode: Text.WordWrap
    font.pixelSize: Appearance.font.pixelSize.small
    color: Appearance.colors.colSubtext
}
