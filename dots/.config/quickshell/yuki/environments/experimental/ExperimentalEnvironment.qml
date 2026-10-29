import QtQuick
import Quickshell

import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.background
import qs.experimental.bluetooth
import qs.experimental.dock
import qs.experimental.filePicker
import qs.experimental.gameBar
import qs.experimental.input
import qs.experimental.launcher
import qs.experimental.lock
import qs.experimental.minimize
import qs.experimental.notifications
import qs.experimental.osd
import qs.experimental.session
import qs.experimental.polkit
import qs.experimental.regionSelect
import qs.experimental.screenShare
import qs.experimental.screenSnip
import qs.experimental.surfaces
import qs.experimental.switcher
import qs.experimental.windows

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

    // One binding for all the centers. Each of them holding its own put back,
    // on closing, whatever it found when it opened, which with two screens is
    // the other center's true: the flag then stayed up after both had closed
    // and every later notification was held back from popping up.
    Binding {
        target: Notifications
        property: "viewerOpen"
        value: ExStates.notificationViewers > 0
    }

    ExSurfaces {}

    // Copies are kept from the start, whether or not the history is ever opened.
    Component.onCompleted: ExClipboardHistory.load()

    ExPlacement {
        id: placement
    }
    ExGestures {}
    ExSnap {
        placement: placement
    }

    PanelLoader { component: ExBackground {} }
    PanelLoader { component: ExDock {} }
    PanelLoader { component: ExLauncher {} }
    PanelLoader { component: ExSwitcher {} }
    PanelLoader { component: ExNotificationPopups {} }
    PanelLoader { component: ExLock {} }
    PanelLoader { component: ExPolkit {} }
    PanelLoader { component: ExOSD {} }
    PanelLoader { component: ExSession {} }
    PanelLoader { component: ExBluetoothPairing {} }
    PanelLoader { component: ExScreenSharePicker {} }
    PanelLoader { component: ExRegionSelection {} }
    PanelLoader { component: ExScreenSnip {} }
    PanelLoader { component: ExFilePicker {} }
    PanelLoader { component: ExGameBar {} }
}
