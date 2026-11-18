import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// One step of the welcome: what it is about, said large, a line on why, and
// under them what is chosen in it.
ColumnLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    /** The welcome itself, for a step that moves it on or closes it. */
    property var welcome
    default property alias content: body.data

    readonly property var metrics: ExLooks.settings

    spacing: 6

    ExText {
        Layout.fillWidth: true
        text: root.title
        font.pixelSize: root.metrics.display
        font.weight: ExLooks.font.weightTitle
    }
    ExText {
        Layout.fillWidth: true
        visible: root.subtitle.length > 0
        text: root.subtitle
        font.pixelSize: root.metrics.body
        wrapMode: Text.Wrap
        dim: true
    }
    ColumnLayout {
        id: body

        Layout.fillWidth: true
        Layout.topMargin: root.metrics.groupGap - 6
        spacing: root.metrics.groupGap
    }
}
