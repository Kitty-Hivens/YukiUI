//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Controls
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.looks
import qs.experimental.settings

// The experimental environment's settings, a window and a process of their own
// like the other environments' settings. It closes itself when the desktop
// changes to another environment, the way a panel unmaps itself, since nothing
// else holds it.
ApplicationWindow {
    id: root

    readonly property bool mine: Config.options?.panelFamily === "experimental"
    onMineChanged: {
        if (!root.mine)
            root.close();
    }

    // Deliberately not translated: it is what a window rule would match on.
    title: "Experimental Settings"
    visible: true
    width: 1120
    height: 760
    minimumWidth: 640
    minimumHeight: 440
    color: ExLooks.colors.background
    onClosing: {
        // The countdown dies with this process, so a layout nobody kept is
        // taken back by a command that outlives it.
        if (content.displaysTouched)
            Displays.revertDetached();
        Qt.quit();
    }

    Component.onCompleted: Config.readWriteDelay = 0

    ExSettings {
        id: content
        anchors.fill: parent
        startPage: Quickshell.env("YUKIUI_SETTINGS_PAGE") ?? ""
        focus: true
        Keys.onEscapePressed: root.close()
    }
}
