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
import qs.blueberry.looks
import qs.blueberry.welcome

// Blueberry's welcome, a window and a process of its own like its settings:
// opened by the shell on the first start, and by Super+Shift+Alt+/ after.
// A few steps, each taking effect as it is chosen.
ApplicationWindow {
    id: root

    // Deliberately not translated: it is what a window rule would match on.
    title: "Blueberry Welcome"
    visible: true
    width: 960
    height: 660
    minimumWidth: 820
    minimumHeight: 560
    color: ExLooks.settings.window
    onClosing: Qt.quit()

    Component.onCompleted: Config.readWriteDelay = 0

    // Whether the desktop is light or dark, read from the palette the shell's
    // theme loader reads, as the settings window does. Read before the first
    // frame, and followed, so the window turns with the mode chosen in it.
    FileView {
        id: palette

        path: Directories.generatedMaterialThemePath
        blockLoading: true
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

    ExWelcome {
        anchors.fill: parent
        startStep: Quickshell.env("YUKIUI_WELCOME_STEP") ?? ""
        focus: true
        onFinished: root.close()
    }
}
