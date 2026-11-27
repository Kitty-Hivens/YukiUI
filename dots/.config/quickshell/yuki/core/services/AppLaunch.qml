pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

/**
 * Starts applications from their desktop entries, on the second graphics card
 * when the entry asks for it.
 *
 * An entry asks with PrefersNonDefaultGPU, and Steam does: GNOME and KDE start
 * it on the discrete card, and the games it starts run there with it. Started
 * here as Quickshell starts any entry, it ran on the card that drives the screen,
 * and so did every game on OpenGL, Minecraft among them, unless each was given
 * prime-run by hand. Which entries ask and how the second card is reached are
 * worked out by scripts/apps/second-gpu.py, as the shell starts and whenever
 * the installed applications change. On a machine with one card nothing asks
 * and every entry starts as before.
 */
Singleton {
    id: root

    /** Ids of the entries that ask to run on the second card. */
    property var preferring: ({})
    /** What a program is started with to run on the second card, or empty. */
    property var environment: ({})
    readonly property bool hasSecondGpu: Object.keys(root.environment).length > 0

    function load() {}

    /** Whether an entry asks for the second card itself. */
    function asksForSecondGpu(entry): bool {
        return !!entry && root.preferring[entry.id] === true;
    }

    /**
     * Whether an entry will be started on the second card: as the settings say
     * for it, and otherwise as the entry asks.
     */
    function onSecondGpu(entry): bool {
        if (!root.hasSecondGpu || !entry)
            return false;
        if ((Config.options?.apps.firstGpu ?? []).includes(entry.id))
            return false;
        if ((Config.options?.apps.secondGpu ?? []).includes(entry.id))
            return true;
        return root.asksForSecondGpu(entry);
    }

    function run(entry) {
        if (!entry)
            return;
        if (!root.onSecondGpu(entry)) {
            entry.execute();
            return;
        }
        Quickshell.execDetached({
            command: entry.command,
            workingDirectory: entry.workingDirectory,
            environment: root.environment
        });
    }

    /** One of an entry's actions, on the card the entry itself is started on. */
    function runAction(entry, action) {
        if (!action)
            return;
        if (!root.onSecondGpu(entry)) {
            action.execute();
            return;
        }
        Quickshell.execDetached({
            command: action.command,
            workingDirectory: entry.workingDirectory,
            environment: root.environment
        });
    }

    function refresh() {
        reader.running = false;
        reader.running = true;
    }

    Component.onCompleted: root.refresh()

    // Applications installed or removed change which entries ask. The list is
    // rebuilt as a whole each time, so this waits for the rebuild to settle.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            rescan.restart();
        }
    }
    Timer {
        id: rescan
        interval: 2000
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        command: ["python3", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/apps/second-gpu.py"))]
        stdout: StdioCollector {
            onStreamFinished: {
                let answer;
                try {
                    answer = JSON.parse(text);
                } catch (error) {
                    return;
                }
                const preferring = ({});
                for (const id of answer.entries ?? [])
                    preferring[id] = true;
                root.preferring = preferring;
                root.environment = answer.environment ?? ({});
                if (root.hasSecondGpu)
                    console.log(`[AppLaunch] second card reached through ${answer.source}, ${Object.keys(preferring).length} applications ask for it`);
            }
        }
    }
}
