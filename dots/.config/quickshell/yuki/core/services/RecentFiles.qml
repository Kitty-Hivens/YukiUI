pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The files opened on this desktop lately.
 *
 * Read from the list the toolkits already keep between them -- `recently-used.xbel`,
 * written by GTK and read by every file dialog on the machine -- rather than by
 * watching anything. No new record of what gets opened is created to build this,
 * and the file is only read while the section that shows it is switched on.
 */
Singleton {
    id: root

    readonly property int limit: 6
    readonly property bool wanted: Config.options.waffles.startMenu.showRecentFiles

    /// Newest visit first.
    readonly property var entries: {
        if (!root.wanted)
            return [];
        return root.parse(recentFileView.text());
    }

    /**
     * Pulls the bookmarks out of the file.
     *
     * By pattern rather than by parsing the document: it is machine-written, one
     * bookmark to an element, and it runs to the better part of a megabyte here --
     * which is also why only the opening tags are looked at and the rest is skipped.
     */
    function parse(xml) {
        if (!xml)
            return [];
        const found = [];
        const tag = /<bookmark\b([^>]*)>/g;
        let match;
        while ((match = tag.exec(xml)) !== null) {
            const attributes = match[1];
            const href = /href="([^"]*)"/.exec(attributes);
            if (!href)
                continue;
            const visited = /visited="([^"]*)"/.exec(attributes);
            found.push({
                url: href[1],
                visited: visited ? visited[1] : "",
                name: root.nameOf(href[1]),
                directory: root.directoryOf(href[1])
            });
        }
        // The timestamps are ISO 8601 in UTC throughout the file, so they sort as
        // text without being turned into dates first.
        found.sort((a, b) => b.visited.localeCompare(a.visited));
        return found.slice(0, root.limit);
    }

    function nameOf(url) {
        try {
            return decodeURIComponent(url.slice(url.lastIndexOf("/") + 1));
        } catch (error) {
            // A stray percent sign is not worth losing the entry over.
            return url.slice(url.lastIndexOf("/") + 1);
        }
    }

    function directoryOf(url) {
        const path = url.replace(/^file:\/\//, "");
        const cut = path.lastIndexOf("/");
        let directory = cut > 0 ? path.slice(0, cut) : "/";
        try {
            directory = decodeURIComponent(directory);
        } catch (error) {}
        return directory.startsWith(Directories.home) ? `~${directory.slice(Directories.home.length)}` : directory;
    }

    FileView {
        id: recentFileView
        // Not loaded at all unless something is going to show it.
        path: root.wanted ? `${Directories.home}/.local/share/recently-used.xbel` : ""
        watchChanges: true
        onFileChanged: reload()
    }
}
