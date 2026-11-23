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
    readonly property int count: root.packages.length
    /** What can be updated, as { name, from, to, aur }. */
    readonly property var packages: [...root.repoPackages, ...(root.takesAur ? root.aurPackages : [])]
    property var repoPackages: []
    /** Those of the AUR, which checkupdates does not know of. */
    property var aurPackages: []
    readonly property bool takesAur: Config.ready && Config.options.updates.aur
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
        if (root.takesAur)
            checkAurProc.running = true;
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
     * The update as it runs. It is a service of its own rather than a process
     * of the shell: its last step copies the shell's files, which reloads the
     * shell, and would have ended the update with it. What is known of it is
     * read from its log, so it is found again after that reload.
     */
    property bool updating: false
    /** Which step it is in, as the updater names it, and of how many. */
    property string updateStep: ""
    property int updateStepNumber: 0
    property int updateSteps: 4
    /** What it said last, and how far through the packages it is, 0 to 1, or -1. */
    property string updateDetail: ""
    property real updateShare: -1
    /** How the last one ended: "", "done" or "failed", and where it stopped. */
    property string updateOutcome: ""
    property string updateFailedStep: ""
    /** Its latest lines. */
    property var updateLog: []
    readonly property string updateLogPath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/update.log`

    /**
     * Updates everything there is to update, by itself. A command named in the
     * config is run instead, as it always was. Not known where YukiUI came
     * from, the packages alone are upgraded.
     */
    function update() {
        const custom = Config.options.apps.update;
        if (custom.length > 0) {
            Quickshell.execDetached(["bash", "-c", custom]);
            return;
        }
        if (root.updating)
            return;
        const run = root.shellAvailable ? [`${root.repository}/setup`, "update", "--unattended"]
            : ["bash", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/update-packages.sh")), "--service", "--unattended"];
        const args = ["systemd-run", "--user", "--unit=yuki-update", "--collect", "--quiet",
            "-p", "Type=exec", "-p", "StandardInput=null",
            "-p", `StandardOutput=truncate:${root.updateLogPath}`, "-p", `StandardError=append:${root.updateLogPath}`,
            `--setenv=PATH=${Quickshell.env("PATH")}`, ...run];
        if (!root.takesAur)
            args.push("--no-aur");
        startUpdate.command = args;
        startUpdate.running = true;
    }

    /** The update in a terminal, where whatever asks can be answered. */
    function updateInTerminal() {
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
        root.repoPackages = status === 2 ? [] : root.entriesOf(lines, false);
    }

    /** Lines as the checkers print them, "name old -> new". */
    function entriesOf(lines, aur: bool): var {
        return lines.map(line => {
            const parts = line.trim().split(/\s+/);
            return { name: parts[0] ?? "", from: parts[1] ?? "", to: parts[3] ?? "", aur: aur };
        }).filter(entry => entry.name.length > 0 && entry.to.length > 0);
    }

    function begin() {
        root.updateStep = "";
        root.updateStepNumber = 0;
        root.updateDetail = "";
        root.updateShare = -1;
        root.updateOutcome = "";
        root.updateFailedStep = "";
        root.updateLog = [];
        root.missing = 0;
        root.updating = true;
    }

    function end(outcome: string, failedStep: string) {
        if (!root.updating)
            return;
        root.updating = false;
        root.updateOutcome = outcome;
        root.updateFailedStep = failedStep;
        root.refreshAll();
    }

    /** One line of the updater's log. */
    function takeLine(raw) {
        const line = raw.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").replace(/\r/g, "").replace(/\s+$/, "");
        if (line.startsWith("@yuki ")) {
            const parts = line.split(" ");
            if (parts[1] === "step") {
                root.updateStepNumber = parseInt(parts[2]) || 0;
                root.updateSteps = parseInt(parts[3]) || 4;
                root.updateStep = parts[4] ?? "";
                root.updateDetail = "";
                root.updateShare = -1;
            } else if (parts[1] === "done") {
                root.end("done", "");
            } else if (parts[1] === "failed") {
                root.end("failed", parts[2] ?? "");
            }
            return;
        }
        if (line.trim().length === 0)
            return;
        root.updateLog = [...root.updateLog, line].slice(-400);
        root.updateDetail = line.trim();
        // Pacman counts packages as "(3/40) upgrading ...".
        const counted = line.match(/^\s*\((\d+)\/(\d+)\)/);
        if (counted && Number(counted[2]) > 0)
            root.updateShare = Math.min(1, Number(counted[1]) / Number(counted[2]));
    }

    Process {
        id: startUpdate
        onExited: exitCode => {
            if (exitCode === 0)
                root.begin();
        }
    }
    // Still running from before the shell was reloaded, perhaps by it.
    Process {
        id: findUpdate
        running: true
        command: ["systemctl", "--user", "is-active", "--quiet", "yuki-update.service"]
        onExited: exitCode => {
            if (exitCode === 0 && !root.updating)
                root.begin();
        }
    }
    Process {
        running: root.updating
        command: ["tail", "-n", "+1", "-F", root.updateLogPath]
        stdout: SplitParser {
            onRead: line => root.takeLine(line)
        }
    }
    // Ended without saying so, killed say: not left as if it were going on.
    property int missing: 0
    Timer {
        interval: 3000
        repeat: true
        running: root.updating
        onTriggered: checkAlive.running = true
    }
    Process {
        id: checkAlive
        command: ["systemctl", "--user", "is-active", "--quiet", "yuki-update.service"]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.missing = 0;
                return;
            }
            root.missing++;
            if (root.missing >= 2)
                root.end("failed", root.updateStep);
        }
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

    // yay, when it is there, with the AUR packages that have moved on: ends in
    // 1 with none, as it does with the network down, so an empty answer counts
    // as none.
    Process {
        id: checkAurProc
        command: ["bash", "-c", "command -v yay > /dev/null && yay -Qua 2> /dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: root.aurPackages = root.entriesOf(text.trim().split("\n"), true)
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
