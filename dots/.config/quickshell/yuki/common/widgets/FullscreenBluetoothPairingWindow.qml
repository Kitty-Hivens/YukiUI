pragma ComponentBehavior: Bound
import qs.core.services
import QtQuick

/** The pairing prompt, on every screen, for as long as BlueZ is waiting on one. */
FullscreenPromptWindow {
    name: "bluetoothPairing"
    active: BluetoothAgent.active
}
