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
 *
 * Each application gets a systemd scope of its own in app-graphical.slice, as
 * uwsm gives the ones it starts. Started straight from the shell, they ran in
 * the shell's own scope: the memory protected for the shell was shared with a
 * browser and a game, and taking the shell's scope down took them with it.
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

    /** An application was just started, by its entry's id. */
    signal launched(string id)

    function run(entry) {
        if (!entry)
            return;
        root.launched(entry.id);
        root.start(entry.command, entry.workingDirectory, root.onSecondGpu(entry) ? root.environment : ({}), entry.id);
    }

    /** One of an entry's actions, on the card the entry itself is started on. */
    function runAction(entry, action) {
        if (!action)
            return;
        root.launched(entry?.id ?? "");
        root.start(action.command, entry?.workingDirectory ?? "", root.onSecondGpu(entry) ? root.environment : ({}), entry?.id ?? "");
    }

    /**
     * Starts a program the way an application is started, in a scope of its
     * own: a file or a folder opened from the desktop goes through here too,
     * since what opens it is an application. Named after what is started.
     */
    function start(command, workingDirectory: string, environment, name: string) {
        if (!command || command.length === 0)
            return;
        const argv = root.scoped ? ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app-graphical.slice", `--unit=${root.unitFor(name)}`, "--", ...command] : [...command];
        Quickshell.execDetached({
            command: argv,
            workingDirectory: workingDirectory ?? "",
            environment: environment ?? ({})
        });
    }

    /** A unit name as systemd's desktop launchers make them: app-<launcher>-<id>-<random>.scope. */
    function unitFor(name: string): string {
        const id = ((name ?? "").length > 0 ? name : "app").replace(/[^A-Za-z0-9_.]/g, "_").slice(0, 80);
        return `app-yuki-${id}-${Date.now().toString(36)}${Math.floor(Math.random() * 46656).toString(36)}.scope`;
    }

    /**
     * Whether a user manager is there to put scopes in. Without one, on a
     * session not started by systemd, programs start as they did before.
     */
    property bool scoped: false
    Process {
        running: true
        command: ["sh", "-c", "command -v systemd-run > /dev/null && systemctl --user show-environment > /dev/null 2>&1"]
        onExited: exitCode => root.scoped = exitCode === 0
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
