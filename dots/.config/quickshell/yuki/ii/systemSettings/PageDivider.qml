import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common

/**
 * The line between two entries of one card. Between cards there is spacing
 * instead -- a rule there would divide things that are already apart.
 */
Rectangle {
    Layout.fillWidth: true
    Layout.topMargin: 12
    Layout.bottomMargin: 12
    implicitHeight: 1
    color: Appearance.colors.colLayer0Border
}
