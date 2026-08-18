import QtQuick
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets

QuickToggleModel {
    name: Translation.tr("Screen snip")
    hasStatusText: false
    toggled: false
    icon: "screenshot_region"

    mainAction: () => {
        GlobalStates.panelDismissRequested();
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
        }
    }

    tooltipText: Translation.tr("Screen snip")
}
