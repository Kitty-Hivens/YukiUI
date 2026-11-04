import QtQuick

import qs.core.services
import qs.blueberry.looks

// Forgetting takes the password or the pairing with it, and one stray click
// should not. The first press asks, a second within a few seconds does it.
ExButton {
    id: root

    property bool asking: false

    signal confirmed

    kind: root.asking ? "accent" : "control"
    text: root.asking ? Translation.tr("Really forget?") : Translation.tr("Forget")
    onClicked: {
        if (!root.asking) {
            root.asking = true;
            settle.restart();
            return;
        }
        root.asking = false;
        settle.stop();
        root.confirmed();
    }

    Timer {
        id: settle
        interval: 3500
        onTriggered: root.asking = false
    }
}
