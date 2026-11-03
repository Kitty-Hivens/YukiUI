pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.core.functions

/**
 * Which backend answers each portal request, read and changed through
 * portals.py, for a family's settings page to draw.
 *
 * xdg-desktop-portal resolves an interface by walking a preference list and
 * publishes the answer nowhere, not on the bus, not in its log. So "who draws
 * my file chooser" can only be answered by redoing the resolution, which is
 * what portals.py does. Kept apart from any page: each family draws the page
 * with its own kit, and what it shows is the same.
 */
Scope {
    id: root

    // Asked of the shell rather than resolved against this file: the scanner
    // serves shell files through a qs:@/ scheme, so a relative URL from here is
    // not a path anything can execute.
    readonly property string helper: FileUtils.trimFileProtocol(Quickshell.shellPath("plugins/portals/portals.py"))

    property var report: null
    /** A change is written but the portal service still runs on the old one. */
    property bool restartNeeded: false
    property string lastError: ""

    readonly property var interfaces: root.report?.interfaces ?? []
    /** Interfaces with a rule of their own. */
    readonly property var ruled: root.interfaces.filter(row => row.explicit)
    /** Interfaces answered through the default list. */
    readonly property var followed: root.interfaces.filter(row => !row.explicit && row.backend.length > 0)
    /** Interfaces nothing answers. */
    readonly property var unserved: root.interfaces.filter(row => row.backend.length === 0 && !row.disabled)
    readonly property var backends: root.report?.backends ?? []
    /** Files that exist, are not the one in force, and therefore do nothing. */
    readonly property var shadowed: (root.report?.config?.candidates ?? []).filter(entry => entry.exists && !entry.active)
    /** The configuration file in force. */
    readonly property string activeConfig: root.report?.config?.active ?? ""

    /** The default list, as the file spells it. */
    readonly property var defaultChain: {
        const row = root.interfaces.find(entry => !entry.explicit);
        return row ? row.preference : [];
    }

    /** "" to follow the default, a backend's name, or "none" for no answer. */
    function setPreference(interfaceName: string, value: string): void {
        writeProcess.running = false;
        writeProcess.command = ["python3", root.helper, "set", interfaceName, value];
        writeProcess.running = true;
    }

    function restart(): void {
        restartProcess.running = true;
    }

    function reread(): void {
        readProcess.running = false;
        readProcess.running = true;
    }

    /** What a row is set to, as setPreference takes it. */
    function currentValue(row): string {
        return row.explicit ? (row.disabled ? "none" : row.backend) : "";
    }

    /** Backends named in a row's preference that are not installed at all. */
    function missingFor(row): var {
        return row.skipped.filter(name => name.indexOf("(") !== -1).map(name => name.split(" ")[0]);
    }

    Component.onCompleted: readProcess.running = true

    Process {
        id: readProcess
        command: ["python3", root.helper, "report"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.report = JSON.parse(text);
                    root.lastError = "";
                } catch (error) {
                    root.lastError = Translation.tr("Could not read the portal configuration");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
    }

    Process {
        id: writeProcess
        onExited: code => {
            if (code === 0)
                root.restartNeeded = true;
            root.reread();
        }
    }

    Process {
        id: restartProcess
        command: ["systemctl", "--user", "restart", "xdg-desktop-portal.service"]
        onExited: {
            root.restartNeeded = false;
            root.reread();
        }
    }
}
