pragma ComponentBehavior: Bound
import qs.core.services
import qs.core
import qs.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.ii.overlay.crosshair
import qs.ii.overlay.volumeMixer
import qs.ii.overlay.floatingImage
import qs.ii.overlay.fpsLimiter
import qs.ii.overlay.recorder
import qs.ii.overlay.resources
import qs.ii.overlay.notes

DelegateChooser {
    id: root
    role: "identifier"

    DelegateChoice { roleValue: "crosshair"; Crosshair {} }
    DelegateChoice { roleValue: "floatingImage"; FloatingImage {} }
    DelegateChoice { roleValue: "fpsLimiter"; FpsLimiter {} }
    DelegateChoice { roleValue: "recorder"; Recorder {} }
    DelegateChoice { roleValue: "resources"; Resources {} }
    DelegateChoice { roleValue: "notes"; Notes {} }
    DelegateChoice { roleValue: "volumeMixer"; VolumeMixer {} }
}
