import qs.core.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.ii.onScreenDisplay

OsdValueIndicator {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property var brightnessMonitor: Brightness.getMonitorForScreen(focusedScreen)

    icon: Hyprsunset.temperatureActive ? "routine" : "light_mode"
    rotateIcon: true
    scaleIcon: true
    name: Translation.tr("Brightness")
    value: root.brightnessMonitor?.brightness ?? 50
}
