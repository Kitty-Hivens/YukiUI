pragma Singleton
pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

/**
 * Builds what is found in `plugins/`, and nothing that is not.
 *
 * A static `import` cannot express "optional": a directory that is not there is
 * a load failure for the whole shell rather than a feature that is absent. So
 * nothing here names a plugin. The host reads each manifest -- inert JSON, so a
 * plugin is enumerated without running any of its code -- and builds the entry
 * it declares.
 *
 * Reached by id rather than by type, because a type name has to exist when the
 * shell is parsed and the point of this is that it might not:
 *
 *     Plugins.get("cloudflareWarp")?.available ?? false
 */
Singleton {
    id: root

    /** The one API generation this host knows how to build. */
    readonly property int apiVersion: 1

    readonly property string pluginPath: FileUtils.trimFileProtocol(Quickshell.shellPath("plugins"))
    readonly property url pluginFolder: Qt.resolvedUrl(Quickshell.shellPath("plugins"))

    /**
     * id -> whatever the plugin's entry built.
     *
     * Replaced rather than mutated on every change: a binding watching this
     * property is told when the map changes, and is told nothing at all when a
     * key is added to the same object in place.
     */
    property var loaded: Object.create(null)

    /**
     * What is here, and what of it is running.
     *
     * `ids` means the same thing in both registries -- what is installed -- so
     * that code written against one reads correctly against the other. It used
     * to mean what was running here and what was installed there, which is a
     * trap rather than an API.
     */
    readonly property list<string> ids: root.installedIds

    readonly property list<string> runningIds: Object.keys(root.loaded).sort()

    // Woken from shell.qml, like the other services that have to be running
    // before anything asks them a question.
    function load() {}

    function get(id) {
        return root.loaded[id] ?? null;
    }

    function has(id) {
        return Object.prototype.hasOwnProperty.call(root.loaded, id);
    }

    /**
     * Installed and turned on are different answers.
     *
     * A plugin found on disk but named here is never built, so `ids` lists what
     * is running rather than what is present. `installedIds` is the other half,
     * for a surface that has to offer the switch.
     */
    readonly property list<string> disabledIds: Config.ready ? Config.options.disabledPlugins : []

    readonly property list<string> installedIds: root.slots ? Array.from({ length: root.slots.count }, (_, i) => root.slots.objectAt(i)?.pluginId ?? "").filter(id => id.length > 0).sort() : []

    function isDisabled(id) {
        return root.disabledIds.indexOf(id) !== -1;
    }

    /**
     * What a plugin offers a quick panel, or null when it offers nothing.
     *
     * Looked up by the same string the panels already keep in their config, so
     * a toggle that used to be built into the shell keeps its place in a list
     * the user arranged.
     */
    function quickToggle(id) {
        return root.get(id)?.quickToggle ?? null;
    }

    readonly property list<string> quickToggleIds: root.runningIds.filter(id => !!root.loaded[id]?.quickToggle)

    /**
     * Which directory holds which id.
     *
     * Two directories declaring the same id used to overwrite each other in the
     * registry: the first instance stayed alive with its processes and shortcuts
     * but could no longer be reached, and unregistering either one erased the
     * entry for both. Copying a plugin next to itself was enough to do it.
     */
    property var claims: Object.create(null)

    /**
     * Why a directory under `plugins/` is not running, keyed by directory name.
     *
     * A refusal used to exist only as a line in the journal, which is to say it
     * did not exist for anyone who was not watching one. What a person sees is a
     * plugin that is simply absent, with no way to ask why. Kept here so a
     * surface can say it out loud.
     */
    property var problems: Object.create(null)

    /**
     * An id becomes a file name and a registry key; an entry becomes a url.
     *
     * Neither used to be checked, so a typo in a manifest wrote settings
     * somewhere else entirely, or loaded QML from outside the plugin, and did
     * it without a word. A plugin is code and this is not a barrier -- it is
     * the difference between a mistake that says so and one that does not.
     */
    function usableId(id) {
        return typeof id === "string" && /^[A-Za-z0-9_-]+$/.test(id);
    }

    function usableEntry(entry) {
        return typeof entry === "string" && entry.length > 0
            && !entry.startsWith("/") && entry.split("/").indexOf("..") === -1;
    }

    function reject(directory, reason) {
        console.warn(`[Plugins] ${directory}: ${reason}`);
        const next = Object.assign(Object.create(null), root.problems);
        next[directory] = reason;
        root.problems = next;
    }

    function clearProblem(directory) {
        if (root.problems[directory] === undefined)
            return;
        const next = Object.assign(Object.create(null), root.problems);
        delete next[directory];
        root.problems = next;
    }

    function claim(id, holder) {
        if (root.claims[id] !== undefined && root.claims[id] !== holder)
            return false;
        const next = Object.assign(Object.create(null), root.claims);
        next[id] = holder;
        root.claims = next;
        return true;
    }

    function release(id, holder) {
        if (root.claims[id] !== holder)
            return;
        const next = Object.assign(Object.create(null), root.claims);
        delete next[id];
        root.claims = next;
    }

    function register(id, instance) {
        const next = Object.assign(Object.create(null), root.loaded);
        next[id] = instance;
        root.loaded = next;
    }

    function unregister(id) {
        const next = Object.assign(Object.create(null), root.loaded);
        delete next[id];
        root.loaded = next;
    }

    property Component settingsComponent: Component {
        PluginSettings {}
    }

    /** One directory under `plugins/`, however far it gets. */
    component Slot: QtObject {
        id: slot

        required property string directory
        property string pluginId: ""
        property string entryUrl: ""
        property var instance: null
        /** Defaults the manifest declared, or null when it declared none. */
        property var configSchema: null
        property var settings: null

        function build(text) {
            let manifest;
            try {
                manifest = JSON.parse(text);
            } catch (error) {
                root.reject(slot.directory, "the manifest is not JSON");
                return;
            }
            if (!root.usableId(manifest?.id)) {
                root.reject(slot.directory, `"${manifest?.id}" cannot be an id -- letters, digits, dashes and underscores only`);
                return;
            }
            if (!root.usableEntry(manifest?.entry)) {
                root.reject(slot.directory, `"${manifest?.entry}" cannot be an entry -- a path inside this directory, with no ".." in it`);
                return;
            }
            if (!manifest?.id || !manifest?.entry) {
                root.reject(slot.directory, "the manifest names no id or no entry");
                return;
            }
            // Refused rather than attempted. A plugin written against another
            // generation of this host fails somewhere inside itself instead,
            // and that failure is much harder to read than this line.
            if (manifest.apiVersion !== root.apiVersion) {
                root.reject(slot.directory, `it wants API ${manifest.apiVersion}, this host speaks ${root.apiVersion}`);
                return;
            }
            if (!root.claim(manifest.id, slot)) {
                root.reject(slot.directory, `the id "${manifest.id}" is already held by another directory`);
                return;
            }
            slot.pluginId = manifest.id;
            slot.entryUrl = `${root.pluginFolder}/${slot.directory}/${manifest.entry}`;
            slot.configSchema = (manifest.config && typeof manifest.config === "object" && !Array.isArray(manifest.config))
                ? manifest.config
                : null;
            slot.sync();
        }

        /**
         * Brings the slot to whatever the config asks for.
         *
         * A plugin turned off is not built at all, rather than built and
         * ignored: its code never runs, so it cannot spawn a process or claim
         * a shortcut while switched off. That is also why this is not decided
         * once at startup -- turning one off has to take it down.
         */
        function sync() {
            if (slot.pluginId.length === 0)
                return;
            // The deny list reads empty until the config has been read, and the
            // manifest and the config are two independent reads with no order
            // between them. Building in that window builds what is switched off
            // -- which on a first run, where there is no config file to read at
            // all, is every time.
            if (!Config.ready)
                return;
            const wanted = !root.isDisabled(slot.pluginId);
            if (wanted === (slot.instance !== null))
                return;
            if (!wanted) {
                root.unregister(slot.pluginId);
                slot.instance.destroy();
                slot.instance = null;
                console.log(`[Plugins] ${slot.pluginId} unloaded`);
                return;
            }
            if (slot.settings === null && slot.configSchema !== null) {
                slot.settings = settingsComponent.createObject(slot, {
                    pluginId: slot.pluginId,
                    schema: slot.configSchema
                });
            }
            const component = Qt.createComponent(slot.entryUrl);
            if (component.status === Component.Error) {
                root.reject(slot.directory, component.errorString());
                return;
            }
            // Handed in at construction rather than assigned after, so a plugin
            // can bind to its own settings from its first line.
            const instance = component.createObject(slot, {
                settings: slot.settings?.values ?? null
            });
            if (!instance) {
                root.reject(slot.directory, "the entry built nothing");
                return;
            }
            slot.instance = instance;
            root.clearProblem(slot.directory);
            root.register(slot.pluginId, instance);
            console.log(`[Plugins] ${slot.pluginId} loaded`);
        }

        readonly property var disabledWatch: root.disabledIds
        onDisabledWatchChanged: slot.sync()

        // Watched on its own: where nothing is switched off, the list reads the
        // same before and after the config arrives, so it never signals.
        readonly property bool configReady: Config.ready
        onConfigReadyChanged: slot.sync()

        property FileView manifestFile: FileView {
            path: `${root.pluginPath}/${slot.directory}/manifest.json`
            onLoaded: slot.build(text())
            onLoadFailed: root.reject(slot.directory, "there is no manifest here")
        }

        Component.onDestruction: {
            if (slot.pluginId.length === 0)
                return;
            if (slot.instance !== null)
                root.unregister(slot.pluginId);
            root.release(slot.pluginId, slot);
        }
    }

    /**
     * The directory names, replaced only when they actually differ.
     *
     * The folder model resets on any change under `plugins/`, and a slot list
     * driven straight off it was destroyed and rebuilt entire every time:
     * processes restarted, shortcuts were dropped and registered again, and
     * contributed toggles vanished from the panels while it happened. A file
     * being written inside a plugin is not a plugin being installed, and neither
     * is an editor saving one.
     *
     * So the model is read into a list, and the list is only replaced when the
     * set of directories is not what it was. Bursts are collected first, because
     * an install writes many files and each one is a reset.
     */
    property var directories: []

    function rescan() {
        const names = [];
        for (let i = 0; i < folders.count; i++)
            names.push(folders.get(i, "fileName"));
        names.sort();
        const same = names.length === root.directories.length
            && names.every((name, i) => name === root.directories[i]);
        if (same)
            return;
        root.directories = names;
    }

    property Timer settleTimer: Timer {
        interval: 100
        onTriggered: root.rescan()
    }

    property FolderListModel folders: FolderListModel {
        id: folders
        folder: root.pluginFolder
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onCountChanged: settleTimer.restart()
        onStatusChanged: if (status === FolderListModel.Ready) settleTimer.restart()
    }

    property Instantiator slots: Instantiator {
        model: root.directories
        delegate: Slot {
            required property string modelData
            directory: modelData
        }
    }

    /**
     * What is here, what is running, and what is wrong with the rest.
     *
     * The model already knew all three; nothing could ask it. Turning a plugin
     * off meant editing the config file by hand, and a plugin refused for a bad
     * manifest looked exactly like a plugin nobody installed.
     */
    function report(): string {
        const rows = [];
        for (let i = 0; i < (root.slots?.count ?? 0); i++) {
            const slot = root.slots.objectAt(i);
            if (!slot)
                continue;
            const problem = root.problems[slot.directory] ?? "";
            const id = slot.pluginId.length > 0 ? slot.pluginId : "-";
            const state = slot.instance !== null ? "running" : (problem.length > 0 ? "broken" : (root.isDisabled(id) ? "off" : "pending"));
            rows.push([id, state, slot.directory, problem]);
        }
        if (rows.length === 0)
            return "no plugins installed";
        const width = Math.max(...rows.map(row => row[0].length));
        return rows.map(row => `${row[0].padEnd(width)}  ${row[1].padEnd(7)}  ${row[2]}${row[3].length > 0 ? "  -- " + row[3] : ""}`).join("\n");
    }

    function setDisabled(id, off): string {
        if (!Config.ready)
            return "the config has not been read yet, try again";
        const known = root.installedIds.indexOf(id) !== -1;
        if (!known)
            return `no plugin here is called "${id}"`;
        const current = Config.options.disabledPlugins;
        const wanted = off ? (current.indexOf(id) === -1 ? current.concat([id]) : current)
                           : current.filter(other => other !== id);
        if (wanted.length === current.length && off === (current.indexOf(id) !== -1))
            return `${id} is already ${off ? "off" : "on"}`;
        Config.options.disabledPlugins = wanted;
        return `${id} is now ${off ? "off" : "on"}`;
    }

    IpcHandler {
        target: "plugins"

        function list(): string {
            return root.report();
        }
        function enable(id: string): string {
            return root.setDisabled(id, false);
        }
        function disable(id: string): string {
            return root.setDisabled(id, true);
        }
    }
}
