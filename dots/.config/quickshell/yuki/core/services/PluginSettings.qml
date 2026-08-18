pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

/**
 * One plugin's settings, in a file of its own.
 *
 * The shell's own config cannot hold these. Its adapter serializes by walking
 * the properties it declares and building a fresh object, so a key the adapter
 * does not know about is not preserved -- it is erased by the next write of any
 * setting at all. A plugin the shell has never heard of cannot declare anything
 * there, so it gets its own file instead.
 *
 * The schema is inert JSON from the manifest, and the adapter is generated from
 * it here. That way a plugin describes its settings as data and still gets
 * typed properties with change signals, without shipping QML that runs before
 * anyone asked for it.
 */
QtObject {
    id: root

    required property string pluginId
    /** Defaults, as declared in the manifest. Shape and types come from these. */
    required property var schema

    readonly property string directory: FileUtils.trimFileProtocol(`${Directories.shellConfig}/plugins`)
    readonly property string path: `${root.directory}/${root.pluginId}.json`

    /** The generated adapter. Null when the schema could not be expressed. */
    property var values: null

    /** True once the file has been read at least once. Nothing is written before. */
    property bool ready: false

    /**
     * A file that exists but does not parse is left alone.
     *
     * Same rule the shell's own config follows: coming up on defaults is
     * survivable, writing them over a file damaged while the machine was off is
     * not.
     */
    property bool contentsUnreadable: false

    function quote(text) {
        return `"${String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
    }

    /** One JSON value, as the QML property declaration that holds it. */
    function declarationFor(key, value, indent) {
        const pad = " ".repeat(indent);
        if (value === null || value === undefined)
            return `${pad}property var ${key}: null`;
        if (typeof value === "boolean")
            return `${pad}property bool ${key}: ${value}`;
        if (typeof value === "number")
            return Number.isInteger(value) ? `${pad}property int ${key}: ${value}` : `${pad}property real ${key}: ${value}`;
        if (typeof value === "string")
            return `${pad}property string ${key}: ${root.quote(value)}`;
        if (Array.isArray(value))
            return `${pad}property var ${key}: ${JSON.stringify(value)}`;
        // An object becomes a nested JsonObject rather than a var, because a var
        // changed in place raises no signal and the change is then never saved.
        const inner = Object.keys(value).map(child => root.declarationFor(child, value[child], indent + 4)).join("\n");
        return `${pad}property JsonObject ${key}: JsonObject {\n${inner}\n${pad}}`;
    }

    function buildAdapter() {
        const keys = Object.keys(root.schema ?? {});
        if (keys.length === 0)
            return null;
        const body = keys.map(key => root.declarationFor(key, root.schema[key], 4)).join("\n");
        const text = `import Quickshell.Io\n\nJsonAdapter {\n${body}\n}\n`;
        try {
            return Qt.createQmlObject(text, root, `plugin-settings-${root.pluginId}`);
        } catch (error) {
            console.warn(`[PluginSettings] ${root.pluginId}: the declared settings cannot be expressed --`, error);
            return null;
        }
    }

    // Built before the view is given a path, never after: the adapter is filled
    // from the file when the file arrives, and a view that already loaded would
    // hand a late adapter nothing.
    Component.onCompleted: {
        root.values = root.buildAdapter();
        if (root.values !== null)
            fileView.path = root.path;
    }

    property FileView fileView: FileView {
        id: fileView
        adapter: root.values
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onAdapterUpdated: writeTimer.restart()
        onLoaded: {
            const text = fileView.text();
            root.contentsUnreadable = text.trim().length > 0 && !root.parses(text);
            if (root.contentsUnreadable)
                console.error(`[PluginSettings] ${root.pluginId}: the settings file is not readable as JSON, running on defaults and refusing to write over it`);
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                return;
            // First run for this plugin. Nothing to lose, so the defaults are
            // written out and the directory made on the way.
            root.ready = true;
            fileView.writeAdapter();
        }
    }

    function parses(text) {
        try {
            const parsed = JSON.parse(text);
            return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed);
        } catch (error) {
            return false;
        }
    }

    property Timer reloadTimer: Timer {
        interval: 50
        onTriggered: fileView.reload()
    }

    property Timer writeTimer: Timer {
        id: writeTimer
        interval: 50
        onTriggered: {
            if (!root.ready || root.contentsUnreadable)
                return;
            fileView.writeAdapter();
        }
    }
}
