//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

import qs.common
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

    // Whether the desktop is light or dark, read from the palette the shell's
    // theme loader reads. The loader itself is not run here: it also registers
    // the global shortcut that switches the mode, which a second process must
    // not do. Without this the window believed it was always dark, so asking
    // for dark from a light desktop did nothing and a wallpaper picked here
    // came out dark.
    FileView {
        id: palette

        path: Directories.generatedMaterialThemePath
        watchChanges: true
        onFileChanged: palette.reload()
        onLoaded: {
            let hex = "";
            try {
                hex = String(JSON.parse(palette.text()).background ?? "").replace("#", "");
            } catch (error) {
                // Caught mid-write. The write that finishes it is reported too.
                return;
            }
            if (hex.length < 6)
                return;
            const r = parseInt(hex.substr(0, 2), 16) / 255;
            const g = parseInt(hex.substr(2, 2), 16) / 255;
            const b = parseInt(hex.substr(4, 2), 16) / 255;
            Appearance.m3colors.darkmode = (Math.max(r, g, b) + Math.min(r, g, b)) / 2 < 0.5;
        }
    }

    ExSettings {
        id: content
        anchors.fill: parent
        startPage: Quickshell.env("YUKIUI_SETTINGS_PAGE") ?? ""
        focus: true
        Keys.onEscapePressed: root.close()
    }
}
