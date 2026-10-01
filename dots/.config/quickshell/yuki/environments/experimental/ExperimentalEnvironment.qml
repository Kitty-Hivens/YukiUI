import QtQuick
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.background
import qs.experimental.bluetooth
import qs.experimental.dock
import qs.experimental.filePicker
import qs.experimental.launcher
import qs.experimental.lock
import qs.experimental.minimize
import qs.experimental.notifications
import qs.experimental.osd
import qs.experimental.session
import qs.experimental.polkit
import qs.experimental.regionSelect
import qs.experimental.screenShare
import qs.experimental.surfaces

// Being built, surface by surface. Nothing is borrowed from the other
// environments, so whatever is not listed below does not exist here yet.
Scope {
    // Minimising is part of how this desktop works, and the dock is where a
    // minimised window comes back from. A Binding, so the service goes back to
    // off when this environment is torn down.
    Binding {
        target: Minimize
        property: "enabled"
        value: true
    }

    ExMinimizeAnimator {
        id: minimizeAnimator
    }
    Binding {
        target: Minimize
        property: "animator"
        value: minimizeAnimator
    }

    ExSurfaces {}

    PanelLoader { component: ExBackground {} }
    PanelLoader { component: ExDock {} }
    PanelLoader { component: ExLauncher {} }
    PanelLoader { component: ExNotificationPopups {} }
    PanelLoader { component: ExLock {} }
    PanelLoader { component: ExPolkit {} }
    PanelLoader { component: ExOSD {} }
    PanelLoader { component: ExSession {} }
    PanelLoader { component: ExBluetoothPairing {} }
    PanelLoader { component: ExScreenSharePicker {} }
    PanelLoader { component: ExRegionSelection {} }
    PanelLoader { component: ExFilePicker {} }
}
