import QtQuick

// A switch for something the system decides, a radio say, which takes its time
// to answer. It shows what was asked at once and goes back only if the system
// has not come round in the end: bound to the system alone, it sprang back under
// the finger and looked refused until the answer came.
ExSwitch {
    id: root

    /** How it stands, as the system says. */
    property bool on: false
    /** How long to wait for the system, in milliseconds. */
    property int patience: 8000

    property bool waiting: false
    property bool asked: false

    signal switched(bool wanted)

    /** The system has answered, whichever way: no need to wait out the patience. */
    function answered() {
        root.waiting = false;
        settle.stop();
    }

    checkable: false
    checked: root.waiting ? root.asked : root.on

    onClicked: {
        root.asked = !root.checked;
        root.waiting = true;
        settle.restart();
        root.switched(root.asked);
    }
    onOnChanged: {
        if (root.waiting && root.on === root.asked)
            root.answered();
    }

    Timer {
        id: settle
        interval: root.patience
        onTriggered: root.waiting = false
    }
}
