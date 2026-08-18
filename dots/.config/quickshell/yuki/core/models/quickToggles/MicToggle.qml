import QtQuick
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets

QuickToggleModel {
    name: Translation.tr("Audio input")
    statusText: toggled ? Translation.tr("Enabled") : Translation.tr("Muted")
    toggled: !Audio.source?.audio?.muted
    icon: Audio.source?.audio?.muted ? "mic_off" : "mic"
    mainAction: () => {
        Audio.toggleMicMute()
    }
    hasMenu: true

    tooltipText: Translation.tr("Audio input | Right-click for volume mixer & device selector")
}
