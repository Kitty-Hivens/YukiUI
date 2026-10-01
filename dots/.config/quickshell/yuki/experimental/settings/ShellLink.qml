import QtQuick
import Quickshell
import Quickshell.Io

/**
 * What the settings ask of the running shell rather than of a service of
 * their own.
 *
 * The settings are a process of their own, and some state lives only in the
 * shell's: keeping awake is an inhibitor the shell holds, do not disturb and
 * the kept notifications are the shell's notification server. A copy of those
 * services here would act on nothing the desktop uses, and a notification
 * server here would take the bus over whenever the shell restarted. So those
 * are read from the shell while the window is open, and changed through it.
 */
QtObject {
    id: root

    property bool keepAwake: false
    property bool doNotDisturb: false
    property int notificationCount: 0
    /** Whether the shell answered the last time it was asked. */
    property bool reachable: true

    readonly property string shell: Quickshell.shellPath("shell.qml")

    function call(target: string, fn: string, args) {
        Quickshell.execDetached(["qs", "-p", root.shell, "ipc", "call", target, fn, ...(args ?? []).map(arg => String(arg))]);
        poll.restart();
        // Read back a moment later, so the switch follows what happened.
        settle.restart();
    }

    function setKeepAwake(on: bool) {
        root.keepAwake = on;
        root.call("idle", on ? "enable" : "disable", []);
    }

    function setDoNotDisturb(on: bool) {
        root.doNotDisturb = on;
        root.call("notifications", "setSilent", [on]);
    }

    function clearNotifications() {
        root.call("notifications", "clear", []);
    }

    readonly property Process reader: Process {
        command: ["sh", "-c", "qs -p \"$1\" ipc call idle status && qs -p \"$1\" ipc call notifications silent && qs -p \"$1\" ipc call notifications count", "shell-link", root.shell]
        stdout: StdioCollector {
            id: answers

            onStreamFinished: {
                const lines = answers.text.trim().split("\n");
                root.reachable = lines.length >= 3;
                if (!root.reachable)
                    return;
                root.keepAwake = lines[0].trim() === "inhibiting";
                root.doNotDisturb = lines[1].trim() === "on";
                root.notificationCount = parseInt(lines[2].trim()) || 0;
            }
        }
    }

    readonly property Timer poll: Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 1500
        onTriggered: root.reader.running = true
    }

    readonly property Timer settle: Timer {
        interval: 300
        onTriggered: root.reader.running = true
    }
}
