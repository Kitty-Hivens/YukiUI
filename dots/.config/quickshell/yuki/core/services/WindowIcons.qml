pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/**
 * Icons for the windows of applications that have no desktop entry to take
 * one from, Minecraft and games among them, which showed a generic icon.
 *
 * Two places they come from. The icon a window gives itself, which the
 * window-icons Hyprland plugin writes where the shell keeps its runtime files,
 * by the window's class: a picture, or the name of an icon in the theme. And
 * for a game Steam started, the Steam application its process says it is,
 * whose icon and desktop entry Steam installed under its own names.
 *
 * Keyed by the class lowercased, with anything but letters, digits, dots,
 * dashes and underscores made an underscore, as the plugin writes them.
 */
Singleton {
    id: root

    readonly property string folder: `${Quickshell.env("YUKI_RUNTIME_DIR") || Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/yuki-window-icons`

    function keyOf(appClass: string): string {
        return (appClass ?? "").toLowerCase().replace(/[^a-z0-9._-]/g, "_");
    }

    /** Pictures by key, as a source that changes when the picture does. */
    property var pictures: ({})
    /** Names of icons in the theme, by key. */
    property var names: ({})
    /** Steam application ids, by key, for windows whose process says it is one. */
    property var steamApps: ({})

    /** The Steam application a window of this class belongs to, or "". */
    function steamAppOf(appClass: string): string {
        return root.steamApps[root.keyOf(appClass)] ?? "";
    }

    /** The name in the theme of the icon a window gave itself, or "". */
    function nameOf(appClass: string): string {
        return root.names[root.keyOf(appClass)] ?? "";
    }

    /** The picture a window gave itself, as an image source, or "". */
    function pictureOf(appClass: string): string {
        return root.pictures[root.keyOf(appClass)] ?? "";
    }

    FolderListModel {
        id: written

        folder: `file://${root.folder}`
        nameFilters: ["*.png", "*.name"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
    }

    // A picture rewritten keeps its path, and an image already loaded from it
    // would be shown on, so its source carries when it was written.
    function collect() {
        const pictures = {};
        const names = {};
        for (let i = 0; i < written.count; i++) {
            const fileName = written.get(i, "fileName");
            const key = fileName.replace(/\.(png|name)$/, "");
            if (fileName.endsWith(".png"))
                pictures[key] = `file://${written.get(i, "filePath")}?${written.get(i, "fileModified").getTime()}`;
        }
        for (let i = 0; i < reader.count; i++) {
            const holder = reader.objectAt(i);
            if (holder?.loadedName)
                names[holder.key] = holder.loadedName;
        }
        root.pictures = pictures;
        root.names = names;
    }

    // The names, read whole from each file and handed on as they change.
    Instantiator {
        id: reader

        model: written
        delegate: QtObject {
            id: nameHolder

            required property string fileName
            required property string filePath
            readonly property string key: fileName.replace(/\.(png|name)$/, "")
            property string loadedName: ""

            property FileView file: FileView {
                path: nameHolder.fileName.endsWith(".name") ? nameHolder.filePath : ""
                watchChanges: true
                onFileChanged: reload()
                onLoaded: {
                    nameHolder.loadedName = text().trim();
                    root.collect();
                }
            }
        }
    }

    Connections {
        target: written
        function onCountChanged() {
            root.collect();
        }
        function onDataChanged() {
            root.collect();
        }
    }

    // Steam starts a game as a child of its own, and says which application it
    // is in the game's environment. Asked once per class, for windows of a
    // class no desktop entry is named for.
    property var asked: ({})
    property var queue: []

    function askSteam() {
        for (const client of HyprlandData.windowList) {
            const key = root.keyOf(client.class);
            if (!key || root.asked[key] || !(client.pid > 0) || DesktopEntries.byId(client.class))
                continue;
            root.asked[key] = true;
            root.queue = [...root.queue, { key: key, pid: client.pid }];
        }
        if (!steamReader.running && root.queue.length > 0)
            steamReader.next();
    }

    // Made the first time something asks for an icon, by when windows may
    // have been open a while: those are asked about at once.
    Component.onCompleted: root.askSteam()
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.askSteam();
        }
    }

    Process {
        id: steamReader

        property string key: ""

        function next() {
            const job = root.queue[0];
            root.queue = root.queue.slice(1);
            steamReader.key = job.key;
            steamReader.command = ["sh", "-c", "tr '\\0' '\\n' < \"/proc/$1/environ\" 2>/dev/null | grep -m1 '^SteamAppId=' | cut -d= -f2", "steam-app", String(job.pid)];
            steamReader.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const id = text.trim();
                if (/^\d+$/.test(id) && id !== "0") {
                    const next = Object.assign({}, root.steamApps);
                    next[steamReader.key] = id;
                    root.steamApps = next;
                }
            }
        }
        onExited: {
            if (root.queue.length > 0)
                steamReader.next();
        }
    }
}
