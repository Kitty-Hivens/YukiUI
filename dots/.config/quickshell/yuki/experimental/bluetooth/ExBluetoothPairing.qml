import QtQuick

import qs.common.widgets
import qs.experimental.looks

// The pairing prompt, on every screen while BlueZ waits on one. The window
// handling is the shared prompt's, the card is this environment's.
FullscreenBluetoothPairingWindow {
    // Room for the card to leave.
    lingerMs: ExLooks.motion.fast
    contentComponent: Component {
        ExBluetoothPairingContent {}
    }
}
