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

    /** A write asked for before the file had been read, held until it has been. */
    property bool writePending: false
    onReadyChanged: {
        if (root.ready && root.writePending)
            writeTimer.restart();
    }

    /**
     * Whether a key from the manifest can be a property name at all.
     *
     * The adapter is generated as QML source, so a key goes in where an
     * identifier is expected. A hyphen ends the declaration early and a leading
     * capital is refused outright, and either one used to take the whole set
     * down with it -- the plugin then ran on its defaults and never wrote a file.
     */
    function validKey(key) {
        // `saveRequested` is the adapter's own, see buildAdapter.
        return /^[a-z_][A-Za-z0-9_]*$/.test(key) && key !== "saveRequested";
    }

    function usableKeys(object, where) {
        const keys = Object.keys(object ?? {});
        const good = keys.filter(key => root.validKey(key));
        for (const key of keys.filter(key => !root.validKey(key)))
            console.warn(`[PluginSettings] ${root.pluginId}: ${where}"${key}" cannot be a setting name, skipped -- names start with a lower-case letter and hold letters, digits and underscores`);
        return good;
    }

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
        // A list stays a var: there is no list equivalent of JsonObject to hide
        // behind. Changed in place it raises no signal, so a plugin that pushes
        // to one has to say `settings.saveRequested()` afterwards.
        if (Array.isArray(value))
            return `${pad}property var ${key}: ${JSON.stringify(value)}`;
        // An object becomes a nested JsonObject rather than a var, because a var
        // changed in place raises no signal and the change is then never saved.
        const inner = root.usableKeys(value, `${key}.`).map(child => root.declarationFor(child, value[child], indent + 4)).join("\n");
        return `${pad}property JsonObject ${key}: JsonObject {\n${inner}\n${pad}}`;
    }

    function buildAdapter() {
        const keys = root.usableKeys(root.schema, "");
        if (keys.length === 0)
            return null;
        const body = keys.map(key => root.declarationFor(key, root.schema[key], 4)).join("\n");
        // A list is a var, and a var changed in place raises no signal, so the
        // change would never be written. Rather than leave that as a rule to
        // remember, the adapter carries a way to ask: `settings.saveRequested()`.
        const text = `import Quickshell.Io\n\nJsonAdapter {\n    signal saveRequested()\n${body}\n}\n`;
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
        if (root.values === null)
            return;
        root.values.saveRequested.connect(() => writeTimer.restart());
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
            if (error !== FileViewError.FileNotFound) {
                // Anything other than absence -- permissions, a directory in the
                // way -- leaves this unable to save. Said out loud, because the
                // symptom otherwise is settings that simply do not stick.
                console.error(`[PluginSettings] ${root.pluginId}: the settings file could not be read, so nothing will be saved`);
                return;
            }
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
            // Not over contents that could not be read, and not before they have
            // been read at all: the adapter writes every setting at once, so one
            // changed while the file was still loading would put the defaults for
            // all the others over it. Held instead of dropped -- see [Config],
            // which follows the same rule for the shell's own file.
            if (root.contentsUnreadable)
                return;
            if (!root.ready) {
                root.writePending = true;
                return;
            }
            root.writePending = false;
            fileView.writeAdapter();
        }
    }
}
