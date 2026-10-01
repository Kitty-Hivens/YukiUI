import QtQuick

import qs.experimental.looks

// A number between two bounds, stepped down and up, with its unit. Held, the
// buttons keep stepping.
Row {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string unit: ""

    signal edited(real value)

    function step(direction: int) {
        const next = Math.max(root.from, Math.min(root.to, root.value + direction * root.stepSize));
        if (next !== root.value)
            root.edited(next);
    }

    spacing: 2

    ExButton {
        anchors.verticalCenter: parent.verticalCenter
        kind: "control"
        glyph: "remove"
        enabled: root.value > root.from
        autoRepeat: true
        onClicked: root.step(-1)
    }
    ExText {
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        horizontalAlignment: Text.AlignHCenter
        text: root.unit.length > 0 ? `${root.value} ${root.unit}` : `${root.value}`
        role: "label"
    }
    ExButton {
        anchors.verticalCenter: parent.verticalCenter
        kind: "control"
        glyph: "add"
        enabled: root.value < root.to
        autoRepeat: true
        onClicked: root.step(1)
    }
}
