pragma Singleton

import qs.core
import qs.core.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Updates: the system's packages, through checkupdates, which only Arch has,
 * and YukiUI itself, through the repository it was installed from.
 */
Singleton {
    id: root

    /** The checker is installed. Whether it runs by itself is the config's say. */
    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    /** What can be updated, as { name, from, to }. */
    property var packages: []
    /** The last check got no answer, so the figures are those of the one before. */
    property bool failed: false
    /** When a check last got an answer, or null. */
    property var lastChecked: null

    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    /**
     * The repository YukiUI was installed from, as the installer wrote it down,
     * or empty: installed some other way, or by an installer from before it
     * wrote this. Then only the packages are offered.
     */
    property string repository: ""
    readonly property bool shellAvailable: root.repository.length > 0
    property alias shellChecking: checkShellProc.running
    /** How many commits the remote has that the installed copy does not. */
    property int shellBehind: 0
    /** Those commits, newest first, as { hash, subject }. */
    property var shellCommits: []
    /**
     * How the repository stands, as `setup update --check` says: "ok",
     * "dirty" (changes not committed there, which a pull would go over),
     * "detached", "no-upstream", "unreachable" or "diverged", or empty before
     * the first check.
     */
    property string shellState: ""
    property var shellLastChecked: null
    /** There is something to pull, and nothing in the way of pulling it. */
    readonly property bool shellPending: root.shellAvailable && root.shellBehind > 0
        && (root.shellState === "ok" || root.shellState === "unreachable")

    readonly property bool checksByItself: Config.ready && Config.options.updates.enableCheck
    readonly property bool checksShellByItself: Config.ready && Config.options.updates.checkShell && root.shellAvailable
    onChecksByItselfChanged: {
        if (root.checksByItself)
            root.refresh();
    }
    onChecksShellByItselfChanged: {
        if (root.checksShellByItself)
            root.refreshShell();
    }

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }
    function refreshShell() {
        if (!root.shellAvailable || checkShellProc.running)
            return;
        print("[Updates] Checking for YukiUI updates");
        checkShellProc.running = true;
    }
    /** Both, as a press of Check asks. */
    function refreshAll() {
        root.refresh();
        root.refreshShell();
    }

    /**
     * Updates everything there is to update, in a terminal, where whatever
     * asks for a password or a choice can be answered. A command named in the
     * config is run instead, as it always was.
     */
    function update() {
        const custom = Config.options.apps.update;
        if (custom.length > 0) {
            Quickshell.execDetached(["bash", "-c", custom]);
            return;
        }
        const terminal = Config.options.apps.terminal;
        const command = root.shellAvailable
            ? `'${StringUtils.shellSingleQuoteEscape(root.repository)}/setup' update`
            : "bash -c 'if command -v yay >/dev/null; then yay -Syu; else sudo pacman -Syu; fi; read -r -p \"Press Enter to close. \" _'";
        Quickshell.execDetached(["bash", "-c", `${terminal} ${command}`]);
    }

    /**
     * What the checker said, with how it ended on the last line. It ends in 0
     * with updates, in 2 with none, and in anything else without having found
     * out, as it does with the network down. Counted through a pipe, that last
     * case read as nothing to update.
     */
    function take(text) {
        const lines = text.trim().split("\n");
        const status = parseInt((lines.pop() ?? "").replace("status ", ""));
        if (status !== 0 && status !== 2) {
            root.failed = true;
            return;
        }
        root.failed = false;
        root.lastChecked = new Date();
        root.packages = status === 2 ? [] : lines.map(line => {
            const parts = line.trim().split(/\s+/);
            return { name: parts[0] ?? "", from: parts[1] ?? "", to: parts[3] ?? "" };
        }).filter(entry => entry.name.length > 0);
        root.count = root.packages.length;
    }

    /** What `setup update --check` said: a key and its value a line, tab between. */
    function takeShell(text) {
        let state = "";
        let behind = 0;
        const commits = [];
        for (const line of text.split("\n")) {
            const parts = line.split("\t");
            if (parts[0] === "state")
                state = parts[1] ?? "";
            else if (parts[0] === "behind")
                behind = parseInt(parts[1]) || 0;
            else if (parts[0] === "commit" && parts.length >= 3)
                commits.push({ hash: parts[1], subject: parts.slice(2).join("\t") });
        }
        // Nothing readable came back: an old repository without the command,
        // or one that is not there any more. The last answer stands.
        if (state.length === 0)
            return;
        root.shellState = state;
        // A fetch that failed still counts against what was fetched before.
        root.shellBehind = behind;
        root.shellCommits = commits;
        if (state !== "unreachable")
            root.shellLastChecked = new Date();
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: root.checksByItself || root.checksShellByItself
        onTriggered: {
            print("[Updates] Periodic update check due")
            if (root.checksByItself)
                root.refresh();
            if (root.checksShellByItself)
                root.refreshShell();
        }
    }

    // Looked for whether or not it checks by itself: a check by hand needs it too.
    Process {
        id: checkAvailabilityProc
        running: Config.ready
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            if (root.checksByItself)
                root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", "checkupdates; echo \"status $?\""]
        stdout: StdioCollector {
            onStreamFinished: root.take(text)
        }
    }

    FileView {
        id: repositoryFile
        path: `${Directories.shellConfig}/repository`
        watchChanges: true
        // Not there for an install made some other way, which is no error.
        printErrors: false
        onFileChanged: repositoryFile.reload()
        onLoaded: root.repository = repositoryFile.text().trim()
        onLoadFailed: root.repository = ""
    }

    Process {
        id: checkShellProc
        command: ["bash", `${root.repository}/setup`, "update", "--check"]
        stdout: StdioCollector {
            onStreamFinished: root.takeShell(text)
        }
    }

    // Written by the updater as it finishes, which is when both answers change.
    // The terminal it runs in is not the shell's to watch.
    FileView {
        id: updatedStamp
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/updated`
        watchChanges: true
        printErrors: false
        onFileChanged: {
            updatedStamp.reload();
            root.refreshAll();
        }
    }
}
