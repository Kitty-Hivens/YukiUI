pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Takes an application off, as an application's page in the settings asks.
 *
 * Kept here rather than in the page: the settings window builds its pages anew
 * on every step, and a process belonging to a page goes with it, so going back
 * in the middle of a removal stopped flatpak halfway through.
 *
 * What it is handed is what scripts/apps/app-info.py said of the application.
 * Root's part runs through sudo when it lets itself be used without a password,
 * and through the password prompt otherwise.
 */
Singleton {
    id: root

    /** The desktop id being taken off, or empty. */
    property string removing: ""
    readonly property bool busy: remover.running
    /** The desktop id last taken off, once it went. */
    property string removed: ""
    /** Why the last removal did not go through, as the tool said it, or empty. */
    property string problem: ""
    property string problemFor: ""

    signal finished(string id, bool ok)

    function remove(details, withData: bool) {
        if (remover.running || !details)
            return;
        root.problem = "";
        root.problemFor = "";
        const override = details.override ?? "";
        // A copy of the entry the user made goes along: left behind, it would
        // still list an application that is gone.
        const trashOverride = override.length > 0 ? `gio trash -- "$OVERRIDE" || true; ` : "";
        let command;
        if (details.origin === "pacman")
            command = ["bash", "-c", trashOverride + 'if command -v sudo > /dev/null && sudo -n true 2> /dev/null; then exec sudo -n pacman -Rs --noconfirm -- "$1"; elif command -v pkexec > /dev/null; then exec pkexec pacman -Rs --noconfirm -- "$1"; else echo "error: no way to ask for the password, pkexec is not installed" >&2; exit 3; fi', "remove", details.package];
        else if (details.origin === "flatpak")
            command = ["bash", "-c", trashOverride + 'exec flatpak uninstall "--$2" -y --noninteractive $3 -- "$1"', "remove", details.package, details.installation ?? "system", withData ? "--delete-data" : ""];
        else if (details.origin === "user")
            command = ["gio", "trash", "--", details.path];
        else
            return;
        remover.environment = { "OVERRIDE": override };
        remover.command = command;
        root.removing = details.id;
        remover.running = true;
    }

    /** A Steam game: Steam asks for itself and takes it off, in its own window. */
    function removeFromSteam(appId: string) {
        Quickshell.execDetached(["xdg-open", `steam://uninstall/${appId}`]);
    }

    /** The user's copy of an entry put away, so the one installed shows again. */
    function resetOverride(path: string) {
        if (path.length > 0)
            Quickshell.execDetached(["gio", "trash", "--", path]);
    }

    Process {
        id: remover

        stderr: StdioCollector {
            id: said
        }
        onExited: exitCode => {
            const id = root.removing;
            root.removing = "";
            // 126 and 127 are the password prompt dismissed, which is no problem.
            if (exitCode === 0) {
                root.removed = id;
                root.finished(id, true);
                return;
            }
            if (exitCode !== 126 && exitCode !== 127) {
                const lines = said.text.trim().split("\n").filter(line => line.trim().length > 0);
                root.problem = lines.length > 0 ? lines[lines.length - 1].replace(/^error:\s*/, "") : Translation.tr("It could not be taken off, status %1").arg(exitCode);
                root.problemFor = id;
            }
            root.finished(id, false);
        }
    }
}
