import QtQuick
import Quickshell

import qs.core
import qs.waffle
import qs.waffle.actionCenter
import qs.waffle.background
import qs.waffle.bar
import qs.waffle.bluetoothPairing
import qs.waffle.lock
import qs.waffle.notificationCenter
import qs.waffle.notificationPopup
import qs.waffle.onScreenDisplay
// import qs.waffle.overlay
import qs.waffle.polkit
import qs.waffle.screenSnip
import qs.waffle.searchPanel
import qs.waffle.startMenu
import qs.waffle.sessionScreen
import qs.waffle.taskView
import qs.waffle.widgets

// Nothing from the other environment is imported here, and that is the point.
// A cheatsheet, an on-screen keyboard, the overlays, the screen translator and
// the wallpaper picker used to be borrowed from Illogical Impulse. Every one of
// them is drawn in Material You, so borrowing them put a second design system on
// screen inside a Fluent desktop. A surface belongs to whoever draws it, and
// those are drawn by ii. Waffle goes without until it has its own.

Scope {
    // Touched here so it exists from the start: it is what keeps a panel from being
    // mapped over a fullscreen game, and a singleton nobody has asked for yet is a
    // singleton that is not watching.
    Component.onCompleted: WPanels.enforce()

    PanelLoader { component: WaffleActionCenter {} }
    PanelLoader { component: WaffleBar {} }
    PanelLoader { component: WaffleBackground {} }
    PanelLoader { component: WaffleBluetoothPairing {} }
    PanelLoader { component: WaffleLock {} }
    PanelLoader { component: WaffleNotificationCenter {} }
    PanelLoader { component: WaffleNotificationPopup {} }
    PanelLoader { component: WaffleOSD {} }
    // PanelLoader { component: WaffleOverlay {} }
    PanelLoader { component: WafflePolkit {} }
    PanelLoader { component: WScreenSnip {} }
    PanelLoader { component: WaffleSearchPanel {} }
    PanelLoader { component: WaffleStartMenu {} }
    PanelLoader { component: WaffleSessionScreen {} }
    PanelLoader { component: WaffleTaskView {} }
    PanelLoader { component: WaffleWidgets {} }
    PanelLoader { component: WaffleWidgetPicker {} }
}
