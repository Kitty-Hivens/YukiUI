import QtQuick
import Quickshell
import Quickshell.Io

import qs.core.services

/**
 * Counts, progress and requests for attention that applications announce for
 * their launchers, through com.canonical.Unity.LauncherEntry.
 *
 * Only listens, through scripts/launcherEntry/watch.py, since signals on the
 * bus cannot be heard from QML. A taskbar holds one and asks it about each of
 * its applications.
 */
Scope {
    id: root

    /** Lowercased desktop id to { count, countVisible, progress, progressVisible, urgent }. */
    property var entries: ({})

    /** What an application has announced, by the class its windows carry, or null. */
    function stateFor(appId: string): var {
        if (!appId)
            return null;
        const desktopId = (AppSearch.entryFor(appId)?.id ?? appId).toLowerCase();
        return root.entries[desktopId] ?? root.entries[appId.toLowerCase()] ?? null;
    }

    function apply(line: string) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        const app = String(message.app ?? "").toLowerCase();
        if (app.length === 0)
            return;
        const next = Object.assign({}, root.entries);
        if (message.gone) {
            delete next[app];
        } else {
            // A signal carries only what changed, so the rest is kept.
            const previous = next[app] ?? { count: 0, countVisible: false, progress: 0, progressVisible: false, urgent: false };
            next[app] = {
                count: message.count ?? previous.count,
                countVisible: message["count-visible"] ?? previous.countVisible,
                progress: Math.max(0, Math.min(1, message.progress ?? previous.progress)),
                progressVisible: message["progress-visible"] ?? previous.progressVisible,
                urgent: message.urgent ?? previous.urgent
            };
        }
        root.entries = next;
    }

    Process {
        id: watcher

        running: true
        // Its end of stdin closing is what stops it when the shell goes.
        stdinEnabled: true
        command: ["python3", Quickshell.shellPath("scripts/launcherEntry/watch.py")]
        stdout: SplitParser {
            onRead: line => root.apply(line)
        }
        // Started again after a pause if it stops, without flooding the log
        // when it cannot start at all.
        onExited: {
            root.entries = ({});
            restart.start();
        }
    }

    Timer {
        id: restart
        interval: 10000
        onTriggered: watcher.running = true
    }
}
