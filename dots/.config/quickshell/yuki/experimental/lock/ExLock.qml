import QtQuick

import qs.core.panels.lock
import qs.experimental.looks

// The lock: the shared session lock, drawn with this environment's surface.
LockScreen {
    id: root

    // Time for the surface to leave before the lock lets go.
    releaseDelay: ExLooks.motion.normal

    lockSurface: ExLockSurface {
        context: root.context
    }
}
