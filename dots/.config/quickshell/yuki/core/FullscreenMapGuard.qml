import QtQuick

import qs.core.services

// Brings back a layer below the top one that was mapped under a fullscreen
// window. Hyprland 0.57 gives such a layer no fade in and nothing later raises
// it: a wallpaper mapped as the shell restarted during a game stayed unseen for
// good. Only mapping it again with no fullscreen on the screen shows it.
//
// What is fullscreen is not known yet as the layer is made, so a fullscreen seen
// within a moment of that counts as having been there. Bind the layer's
// `visible` to `mapped` along with whatever else decides it.
QtObject {
    id: root

    required property string screenName
    readonly property bool fullscreen: GameMode.fullscreenOn(root.screenName)

    /** The layer may be up. False for one turn of the event loop, to map it anew. */
    property bool mapped: true

    property bool young: true
    property bool unseen: false

    onFullscreenChanged: {
        if (root.fullscreen) {
            if (root.young)
                root.unseen = true;
        } else if (root.unseen) {
            root.unseen = false;
            root.mapped = false;
            Qt.callLater(() => root.mapped = true);
        }
    }

    property Timer settling: Timer {
        interval: 3000
        running: true
        onTriggered: root.young = false
    }

    Component.onCompleted: {
        if (root.fullscreen)
            root.unseen = true;
    }
}
