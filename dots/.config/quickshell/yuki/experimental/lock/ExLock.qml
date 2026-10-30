import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import qs
import qs.core.panels.lock
import qs.experimental.looks

// The lock: the shared session lock, drawn with this environment's surface.
LockScreen {
    id: root

    // Time for the surface to leave before the lock lets go.
    releaseDelay: ExLooks.motion.normal

    /**
     * The lock has been up for as long as its surfaces take to fade in. A
     * surface made after that is for a screen that came, or came back after
     * sleep, while the session was locked, and it shows at once: fading in
     * like the first ones, it showed that screen's desktop through it.
     */
    property bool settled: false
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            root.settled = false;
            if (GlobalStates.screenLocked) {
                settleTimer.restart();
                findCapsLights.running = true;
            } else {
                settleTimer.stop();
            }
        }
    }
    Timer {
        id: settleTimer
        interval: ExLooks.motion.slow
        onTriggered: root.settled = true
    }

    /**
     * Whether Caps Lock is on, read off the keyboards' lights. Hyprland keeps
     * every keyboard's light in step with the one state it holds, and tells a
     * client nothing of it that Qt passes on. Read as the lock comes up and
     * after each key typed into it, never on a timer.
     */
    property bool capsLock: false
    property var capsLights: []

    Process {
        id: findCapsLights
        command: ["sh", "-c", "for light in /sys/class/leds/*::capslock/brightness; do [ -e \"$light\" ] && echo \"$light\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLights = text.split("\n").filter(line => line.length > 0)
        }
    }
    Instantiator {
        id: capsReaders
        model: root.capsLights
        delegate: FileView {
            required property string modelData
            path: modelData
            blockLoading: true
        }
    }
    onCapsLightsChanged: Qt.callLater(root.readCapsLock)

    function readCapsLock() {
        let on = false;
        for (let i = 0; i < capsReaders.count; i++) {
            const reader = capsReaders.objectAt(i);
            if (!reader)
                continue;
            reader.reload();
            const level = reader.text().trim();
            if (level.length > 0 && level !== "0")
                on = true;
        }
        root.capsLock = on;
    }

    // The light changes once the compositor has taken the key, which can be
    // after the key has reached the lock.
    Timer {
        id: capsRead
        interval: 60
        onTriggered: root.readCapsLock()
    }

    lockSurface: ExLockSurface {
        context: root.context
        appearAtOnce: root.settled || root.immediate
        capsLock: root.capsLock
        onKeyTyped: capsRead.restart()
    }
}
