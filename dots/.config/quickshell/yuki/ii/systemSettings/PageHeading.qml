import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * The label above a group of cards. Small and quiet on purpose: it names what
 * follows without competing with the page heading above it.
 */
StyledText {
    Layout.fillWidth: true
    Layout.topMargin: 4
    font.pixelSize: Appearance.font.pixelSize.smallie
    font.weight: Font.Medium
    color: Appearance.colors.colSubtext
}
