import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.waffle
import qs.modules.waffle.actionCenter
import qs.modules.waffle.background
import qs.modules.waffle.bar
import qs.modules.waffle.lock
import qs.modules.waffle.notificationCenter
import qs.modules.waffle.notificationPopup
import qs.modules.waffle.onScreenDisplay
// import qs.modules.waffle.overlay
import qs.modules.waffle.polkit
import qs.modules.waffle.screenSnip
import qs.modules.waffle.searchPanel
import qs.modules.waffle.startMenu
import qs.modules.waffle.sessionScreen
import qs.modules.waffle.taskView
import qs.modules.waffle.widgets

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
