import QtQuick

import qs.common.widgets
import qs.experimental.looks

// The authentication prompt, on every screen while a request is pending. The
// window handling is the shared prompt's. The card is this environment's.
FullscreenPolkitWindow {
    // Room for the card to leave.
    lingerMs: ExLooks.motion.fast
    contentComponent: Component {
        ExPolkitContent {}
    }
}
