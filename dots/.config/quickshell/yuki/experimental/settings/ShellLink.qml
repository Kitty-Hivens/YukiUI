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
    /**
     * Whether anyone is looking: the window holds focus. Read only then, and
     * at once when it comes back, rather than three processes every second and
     * a half for as long as the window is open, in front or not.
     */
    property bool watching: true
    onWatchingChanged: {
        if (root.watching)
            root.reader.running = true;
    }

    readonly property string shell: Quickshell.shellPath("shell.qml")

    /**
     * Asks the shell for a change. The switch has moved already, so it answers
     * under the finger; a shell that does not answer puts it back by the
     * reading that follows, which also says the shell is out of reach.
     */
    function call(target: string, fn: string, args) {
        const caller = callComponent.createObject(root, {
            command: ["qs", "-p", root.shell, "ipc", "call", target, fn, ...(args ?? []).map(arg => String(arg))]
        });
        caller.running = true;
    }

    readonly property Component callComponent: Component {
        Process {
            id: caller
            onExited: exitCode => {
                if (exitCode !== 0)
                    root.reachable = false;
                // Read back, so the switch follows what happened.
                root.reader.running = true;
                caller.destroy();
            }
        }
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
                if (!root.reachable) {
                    // Nothing to follow: what was flipped in advance goes back
                    // to off, which is what an unreachable shell is doing.
                    root.keepAwake = false;
                    root.doNotDisturb = false;
                    return;
                }
                root.keepAwake = lines[0].trim() === "inhibiting";
                root.doNotDisturb = lines[1].trim() === "on";
                root.notificationCount = parseInt(lines[2].trim()) || 0;
            }
        }
    }

    readonly property Timer poll: Timer {
        running: root.watching
        repeat: true
        triggeredOnStart: true
        interval: 4000
        onTriggered: root.reader.running = true
    }
}
