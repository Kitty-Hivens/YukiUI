import QtQuick

import qs
import qs.core.panels.lock
import qs.experimental.looks

// The lock: the shared session lock, drawn with this environment's surface.
LockScreen {
    id: root

    // Time for the surface to leave before the lock lets go.
    releaseDelay: ExLooks.motion.normal

    /**
     * The lock has been up for as long as its surfaces take to fade in. A
     * surface made after that is for a screen that came, or came back after
     * sleep, while the session was locked, and it shows at once: fading in
     * like the first ones, it showed that screen's desktop through it.
     */
    property bool settled: false
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            root.settled = false;
            if (GlobalStates.screenLocked)
                settleTimer.restart();
            else
                settleTimer.stop();
        }
    }
    Timer {
        id: settleTimer
        interval: ExLooks.motion.slow
        onTriggered: root.settled = true
    }

    lockSurface: ExLockSurface {
        context: root.context
        appearAtOnce: root.settled
    }
}
