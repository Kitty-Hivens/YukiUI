import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import QtQuick
import Quickshell
import Quickshell.Wayland

FullscreenPolkitWindow {
    id: root
    contentComponent: Component {
        WPolkitContent {}
    }
}
