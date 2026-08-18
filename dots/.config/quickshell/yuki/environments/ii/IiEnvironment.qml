import QtQuick
import Quickshell

import qs.core
import qs.ii.background
import qs.ii.bar
import qs.ii.cheatsheet
import qs.ii.dock
import qs.ii.lock
import qs.ii.mediaControls
import qs.ii.notificationPopup
import qs.ii.onScreenDisplay
import qs.ii.onScreenKeyboard
import qs.ii.overview
import qs.ii.polkit
import qs.ii.regionSelector
import qs.ii.screenCorners
import qs.ii.screenSharePicker
import qs.ii.screenTranslator
import qs.ii.sessionScreen
import qs.ii.sidebarLeft
import qs.ii.sidebarRight
import qs.ii.overlay
import qs.ii.verticalBar
import qs.ii.wallpaperSelector

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenSharePicker {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
}
