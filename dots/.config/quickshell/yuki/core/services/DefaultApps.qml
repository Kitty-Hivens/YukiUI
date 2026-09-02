pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.functions

/**
 * Which application opens which kind of file, read once and kept.
 *
 * Lives here rather than in the page because the settings window swaps its
 * Loader's source on every navigation, which destroys the page and everything it
 * held. State kept in the page meant a full scan of every installed .desktop
 * entry -- more than a second of it -- each time somebody came back to the page.
 * A service outlives the pages that read it, so the scan happens once.
 *
 * Reading is deliberately not automatic: nothing should walk the application
 * directories in the shell process, where nobody is looking at the result.
 */
Singleton {
    id: root

    readonly property string helper: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/mime/defaults.py"))

    /** The groups as the helper reports them, empty until the first read lands. */
    property var groups: []
    property bool ready: false
    property bool busy: readProcess.running || writeProcess.running
    property string error: ""

    /** Asked for by a page that is about to show this. Reads once. */
    function load() {
        if (root.ready || readProcess.running)
            return;
        readProcess.running = true;
    }

    /** After something changed underneath us, or on demand. */
    function refresh() {
        readProcess.running = false;
        readProcess.running = true;
    }

    /**
     * Points every type of one group at one application.
     *
     * The helper sets only the types that application declares, so a choice
     * cannot write an association that fails the moment it is used.
     */
    function assign(groupKey, applicationId) {
        writeProcess.running = false;
        writeProcess.command = ["python3", root.helper, "set", groupKey, applicationId];
        writeProcess.running = true;
    }

    Process {
        id: readProcess
        command: ["python3", root.helper, "report"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.groups = JSON.parse(text).groups ?? [];
                    root.error = "";
                    root.ready = true;
                } catch (parseError) {
                    root.error = Translation.tr("Could not read the application defaults");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim()
        }
    }

    Process {
        id: writeProcess
        onExited: root.refresh()
    }
}
