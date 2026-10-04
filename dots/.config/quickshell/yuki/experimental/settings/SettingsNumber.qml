import QtQuick

import qs.experimental.looks

// A number between two bounds, stepped down and up, with its unit. Held, the
// buttons keep stepping.
//
// The number steps on the page at once and is told on once the stepping has
// stopped a moment. Told on every step, each one rewrote a config file, the
// compositor's whole config was read again or an idle daemon restarted per
// step, and steps made while the last write settled were dropped.
Row {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string unit: ""

    signal edited(real value)

    /** What is shown: the value, or the one being stepped to. */
    property real shown: root.value
    onValueChanged: {
        if (!settle.running)
            root.shown = root.value;
    }

    function step(direction: int) {
        const next = Math.max(root.from, Math.min(root.to, root.shown + direction * root.stepSize));
        if (next === root.shown)
            return;
        root.shown = next;
        settle.restart();
    }

    Timer {
        id: settle
        interval: 500
        onTriggered: {
            if (root.shown !== root.value) {
                root.edited(root.shown);
                resync.restart();
            }
        }
    }
    // Back on the value once whoever was told has had time to answer: one
    // that refused the change leaves the value as it was, and the number
    // stepped to would go on being shown as if it held.
    Timer {
        id: resync
        interval: 1500
        onTriggered: {
            if (!settle.running)
                root.shown = root.value;
        }
    }

    spacing: 2

    ExButton {
        anchors.verticalCenter: parent.verticalCenter
        kind: "control"
        glyph: "remove"
        enabled: root.shown > root.from
        autoRepeat: true
        onClicked: root.step(-1)
    }
    ExText {
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        horizontalAlignment: Text.AlignHCenter
        text: root.unit.length > 0 ? `${root.shown} ${root.unit}` : `${root.shown}`
        role: "label"
    }
    ExButton {
        anchors.verticalCenter: parent.verticalCenter
        kind: "control"
        glyph: "add"
        enabled: root.shown < root.to
        autoRepeat: true
        onClicked: root.step(1)
    }
}
