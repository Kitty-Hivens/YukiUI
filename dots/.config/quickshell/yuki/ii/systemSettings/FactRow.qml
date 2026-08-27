import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * One thing that is so, as label and value on one line. Hidden when there is no
 * value: a machine that reports nothing for a field is not worth a blank row.
 */
RowLayout {
    id: root
    required property string label
    required property string value

    Layout.fillWidth: true
    visible: root.value.length > 0
    spacing: 16

    StyledText {
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: root.value
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer2
    }
}
