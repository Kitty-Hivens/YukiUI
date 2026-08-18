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
    property var loaded: ({})

    readonly property list<string> ids: Object.keys(root.loaded)

    // Woken from shell.qml, like the other services that have to be running
    // before anything asks them a question.
    function load() {}

    function get(id) {
        return root.loaded[id] ?? null;
    }

    function has(id) {
        return root.loaded[id] !== undefined;
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

    readonly property list<string> quickToggleIds: root.ids.filter(id => !!root.loaded[id]?.quickToggle)

    function register(id, instance) {
        const next = Object.assign({}, root.loaded);
        next[id] = instance;
        root.loaded = next;
    }

    function unregister(id) {
        const next = Object.assign({}, root.loaded);
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
                console.warn(`[Plugins] ${slot.directory}: manifest is not JSON, skipped`);
                return;
            }
            if (!manifest?.id || !manifest?.entry) {
                console.warn(`[Plugins] ${slot.directory}: manifest names no id or no entry, skipped`);
                return;
            }
            // Refused rather than attempted. A plugin written against another
            // generation of this host fails somewhere inside itself instead,
            // and that failure is much harder to read than this line.
            if (manifest.apiVersion !== root.apiVersion) {
                console.warn(`[Plugins] ${manifest.id}: wants API ${manifest.apiVersion}, this host speaks ${root.apiVersion}, skipped`);
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
                console.warn(`[Plugins] ${slot.pluginId}: ${component.errorString()}`);
                return;
            }
            // Handed in at construction rather than assigned after, so a plugin
            // can bind to its own settings from its first line.
            const instance = component.createObject(slot, {
                settings: slot.settings?.values ?? null
            });
            if (!instance) {
                console.warn(`[Plugins] ${slot.pluginId}: the entry built nothing`);
                return;
            }
            slot.instance = instance;
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
            onLoadFailed: console.warn(`[Plugins] ${slot.directory}: no manifest, skipped`)
        }

        Component.onDestruction: {
            if (slot.pluginId.length > 0 && slot.instance !== null)
                root.unregister(slot.pluginId);
        }
    }

    property Instantiator slots: Instantiator {
        model: FolderListModel {
            folder: root.pluginFolder
            showDirs: true
            showFiles: false
            showDotAndDotDot: false
            sortField: FolderListModel.Name
        }
        delegate: Slot {
            required property string fileName
            directory: fileName
        }
    }
}
