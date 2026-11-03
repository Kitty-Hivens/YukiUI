import QtQuick
import Quickshell

import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.background
import qs.blueberry.bluetooth
import qs.blueberry.dock
import qs.blueberry.filePicker
import qs.blueberry.gameBar
import qs.blueberry.input
import qs.blueberry.launcher
import qs.blueberry.lock
import qs.blueberry.minimize
import qs.blueberry.notifications
import qs.blueberry.osd
import qs.blueberry.session
import qs.blueberry.polkit
import qs.blueberry.regionSelect
import qs.blueberry.screenShare
import qs.blueberry.screenSnip
import qs.blueberry.surfaces
import qs.blueberry.switcher
import qs.blueberry.windows

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

    /**
     * Called as another environment takes this one's place. What this desktop
     * keeps on windows is let go of: minimised ones come back now, before the
     * next one comes up and takes the windows over, and placed ones lose the
     * marks they were held by.
     */
    function leave() {
        Minimize.releaseAll();
        placement.releaseAll();
    }

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
