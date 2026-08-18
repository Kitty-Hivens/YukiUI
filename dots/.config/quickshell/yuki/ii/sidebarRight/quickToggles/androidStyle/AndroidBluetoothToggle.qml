import qs.core.services
import qs.core
import qs.core.models.quickToggles
import qs.core.functions
import qs.common.widgets
import QtQuick
import Quickshell
import Quickshell.Bluetooth

AndroidQuickToggleButton {
    id: root
    
    toggleModel: BluetoothToggle {}
}
