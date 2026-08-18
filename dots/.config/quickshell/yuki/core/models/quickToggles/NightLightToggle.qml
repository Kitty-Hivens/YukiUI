import QtQuick
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets

QuickToggleModel {
    property bool auto: Config.options.light.night.automatic

    name: Translation.tr("Night Light")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))

    toggled: Hyprsunset.temperatureActive
    icon: auto ? "night_sight_auto" : "bedtime"
    
    mainAction: () => {
        Hyprsunset.toggleTemperature()
    }
    hasMenu: true

    Component.onCompleted: {
        Hyprsunset.fetchState()
    }
    
    tooltipText: Translation.tr("Night Light | Right-click to configure")
}
