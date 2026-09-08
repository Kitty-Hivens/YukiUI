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
 * Builds the plugins found under either root, and nothing that is not.
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

    /**
     * Where plugins are looked for, and which copy wins when both hold one.
     *
     * Two roots rather than one. The tree the shell is read from belongs to
     * whatever installed it: a copy of it is kept in step with the repository,
     * so it removes whatever the repository does not carry, and where the shell
     * arrives from a store it cannot be written to at all. So what a person
     * installs lives in a root of their own, [Directories.userPlugins].
     *
     * The home root comes first, and a directory there declaring the same id as
     * one that ships with the shell takes it. Putting it there was a deliberate
     * act, and refusing it would be overruling that.
     */
    readonly property string systemRoot: FileUtils.trimFileProtocol(Quickshell.shellPath("plugins"))
    readonly property string homeRoot: Directories.userPlugins

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

    /**
     * Whether this process is the one that runs plugins.
     *
     * Manifests are read anywhere -- that is how a settings window lists what is
     * installed and what it is set to. Building the entries is another matter: a
     * second process that built them would start a second copy of every plugin,
     * with its processes and its shortcuts, behind the back of the shell already
     * running them. So only the process that says so hosts them.
     */
    property bool hosting: false

    // Woken from shell.qml, like the other services that have to be running
    // before anything asks them a question. Saying it is also what marks this
    // process as the host.
    function load() {
        root.hosting = true;
    }

    function get(id) {
        return root.loaded[id] ?? null;
    }

    function has(id) {
        return Object.prototype.hasOwnProperty.call(root.loaded, id);
    }

    /**
     * Installed and turned on are different answers.
     *
     * A plugin found on disk but named here is never built. It stays in `ids`
     * and in `installedIds` all the same: what is installed is one question and
     * what is running is another, and `runningIds` answers the second.
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
     * Why a directory is not running, keyed by its full path.
     *
     * By the path and not by the name: the same name can appear under both
     * roots, and a person's own copy of a plugin is exactly the case where it
     * does.
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

    /**
     * The settings page a manifest declares, checked, or null when it declares none.
     *
     * Refused the same way a bad id or a bad entry is refused -- by taking the
     * whole plugin down -- rather than by dropping the page quietly. A page that
     * silently fails to appear is indistinguishable from a host that does not
     * support pages yet, and that is the harder of the two to debug.
     *
     * `key` is checked as strictly as an id: it is what `componentFor` matches on
     * and what goes into YUKIUI_SETTINGS_PAGE when something opens the window at
     * a particular page.
     */
    function readPage(place, declared) {
        if (declared === undefined || declared === null)
            return null;
        if (typeof declared !== "object" || Array.isArray(declared)) {
            root.reject(place, "settingsPage has to be an object");
            return null;
        }
        if (!root.usableId(declared.key)) {
            root.reject(place, `"${declared.key}" cannot be a page key -- letters, digits, dashes and underscores only`);
            return null;
        }
        if (!root.usableEntry(declared.entry)) {
            root.reject(place, `"${declared.entry}" cannot be a page -- a path inside this directory, with no ".." in it`);
            return null;
        }
        if (typeof declared.name !== "string" || declared.name.length === 0) {
            root.reject(place, "a settings page needs a name");
            return null;
        }
        return {
            key: declared.key,
            name: declared.name,
            icon: typeof declared.icon === "string" && declared.icon.length > 0 ? declared.icon : "extension",
            description: typeof declared.description === "string" ? declared.description : "",
            keywords: typeof declared.keywords === "string" ? declared.keywords : "",
            group: typeof declared.group === "string" ? declared.group : "",
            order: typeof declared.order === "number" ? declared.order : 0,
            entry: declared.entry
        };
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
        const held = root.claims[id];
        if (held === holder)
            return true;
        if (held !== undefined) {
            // Which manifest was read first is not a decision anybody made: the
            // two reads are independent and either can finish ahead of the
            // other. So the root decides, and a copy in the home one takes the
            // id from a copy that ships with the shell.
            if (!holder.fromHome || held.fromHome)
                return false;
            held.standDown(`"${id}" is taken by ${holder.place}`);
        }
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
        Qt.callLater(root.reconsider);
    }

    /**
     * Offers every stood-down directory the id it gave up.
     *
     * Reached when a claim is released, which is what happens when the directory
     * that took an id is removed. Without it, deleting your own copy of a plugin
     * left the one shipped with the shell inert until the next reload, which is
     * a strange way for an uninstall to behave.
     */
    function reconsider() {
        for (let i = 0; i < (root.slots?.count ?? 0); i++) {
            const slot = root.slots.objectAt(i);
            if (slot?.stoodDown)
                slot.build(slot.manifestText);
        }
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

    /** One directory under one of the roots, however far it gets. */
    component Slot: QtObject {
        id: slot

        required property string base
        required property string directory
        /** Both roots can hold a directory of the same name, so this is what
         *  names one of them: it keys the problem list and it is what a refusal
         *  points at. */
        readonly property string place: `${slot.base}/${slot.directory}`
        readonly property bool fromHome: slot.base === root.homeRoot
        /** Kept so a directory that gave up its id can be offered it back
         *  without waiting for the manifest to be read a second time. */
        property string manifestText: ""
        property bool stoodDown: false
        property string pluginId: ""
        /** What the manifest calls itself, for a surface that lists plugins. */
        property string name: ""
        property string entryUrl: ""
        property var instance: null
        /** Defaults the manifest declared, or null when it declared none. */
        property var configSchema: null
        /** The settings page the manifest declared, or null when it declared none. */
        property var settingsPage: null
        property var settings: null

        function build(text) {
            slot.manifestText = text;
            slot.stoodDown = false;
            root.clearProblem(slot.place);
            let manifest;
            try {
                manifest = JSON.parse(text);
            } catch (error) {
                root.reject(slot.place, "the manifest is not JSON");
                return;
            }
            if (!root.usableId(manifest?.id)) {
                root.reject(slot.place, `"${manifest?.id}" cannot be an id -- letters, digits, dashes and underscores only`);
                return;
            }
            if (!root.usableEntry(manifest?.entry)) {
                root.reject(slot.place, `"${manifest?.entry}" cannot be an entry -- a path inside this directory, with no ".." in it`);
                return;
            }
            if (!manifest?.id || !manifest?.entry) {
                root.reject(slot.place, "the manifest names no id or no entry");
                return;
            }
            // Refused rather than attempted. A plugin written against another
            // generation of this host fails somewhere inside itself instead,
            // and that failure is much harder to read than this line.
            if (manifest.apiVersion !== root.apiVersion) {
                root.reject(slot.place, `it wants API ${manifest.apiVersion}, this host speaks ${root.apiVersion}`);
                return;
            }
            if (!root.claim(manifest.id, slot)) {
                root.reject(slot.place, `"${manifest.id}" is taken by ${root.claims[manifest.id].place}`);
                return;
            }
            slot.pluginId = manifest.id;
            slot.name = typeof manifest.name === "string" ? manifest.name : "";
            slot.entryUrl = `file://${slot.place}/${manifest.entry}`;
            slot.configSchema = (manifest.config && typeof manifest.config === "object" && !Array.isArray(manifest.config))
                ? manifest.config
                : null;
            slot.settingsPage = root.readPage(slot.place, manifest.settingsPage);
            // readPage refuses by rejecting the directory, and a rejected plugin
            // is not one to carry on building.
            if (manifest.settingsPage !== undefined && slot.settingsPage === null)
                return;
            // Built here rather than on the way to loading the plugin: settings are
            // host code reading a file, not plugin code, and a surface that offers
            // to configure something has to be able to do it while it is switched
            // off -- otherwise a plugin that needs a setting before it can work
            // cannot be given one.
            if (slot.settings === null && slot.configSchema !== null) {
                slot.settings = settingsComponent.createObject(slot, {
                    pluginId: slot.pluginId,
                    schema: slot.configSchema
                });
            }
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
            const wanted = root.hosting && !root.isDisabled(slot.pluginId);
            if (wanted === (slot.instance !== null))
                return;
            if (!wanted) {
                root.unregister(slot.pluginId);
                slot.instance.destroy();
                slot.instance = null;
                console.log(`[Plugins] ${slot.pluginId} unloaded`);
                return;
            }
            const component = Qt.createComponent(slot.entryUrl);
            if (component.status === Component.Error) {
                root.reject(slot.place, component.errorString());
                return;
            }
            // Handed in at construction rather than assigned after, so a plugin
            // can bind to its own settings from its first line.
            const instance = component.createObject(slot, {
                settings: slot.settings?.values ?? null
            });
            if (!instance) {
                root.reject(slot.place, "the entry built nothing");
                return;
            }
            slot.instance = instance;
            root.clearProblem(slot.place);
            root.register(slot.pluginId, instance);
            console.log(`[Plugins] ${slot.pluginId} loaded`);
        }

        /**
         * Gives the id up to another directory that holds it.
         *
         * The manifest is kept, so this is not final: if the directory that took
         * the id goes away, [reconsider] offers this one its place back.
         */
        function standDown(reason) {
            if (slot.instance !== null) {
                root.unregister(slot.pluginId);
                slot.instance.destroy();
                slot.instance = null;
            }
            slot.pluginId = "";
            slot.stoodDown = true;
            root.reject(slot.place, reason);
        }

        readonly property var disabledWatch: root.disabledIds
        onDisabledWatchChanged: slot.sync()

        // Watched on its own: where nothing is switched off, the list reads the
        // same before and after the config arrives, so it never signals.
        readonly property bool configReady: Config.ready
        onConfigReadyChanged: slot.sync()

        readonly property bool hostingWatch: root.hosting
        onHostingWatchChanged: slot.sync()

        property FileView manifestFile: FileView {
            path: `${slot.place}/manifest.json`
            onLoaded: slot.build(text())
            onLoadFailed: root.reject(slot.place, "there is no manifest here")
        }

        Component.onDestruction: {
            // Said before the early return: a directory turned away never had an
            // id, and its reason would otherwise outlive it in the problem list
            // with nothing left on disk to answer for it.
            root.clearProblem(slot.place);
            if (slot.pluginId.length === 0)
                return;
            if (slot.instance !== null)
                root.unregister(slot.pluginId);
            root.release(slot.pluginId, slot);
        }
    }

    /**
     * One root, and the directory names under it, replaced only when they differ.
     *
     * The folder model resets on any change under the root, and a slot list
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
    component Tree: QtObject {
        id: tree

        required property string base
        property var names: []

        function rescan() {
            const found = [];
            for (let i = 0; i < listing.count; i++)
                found.push(listing.get(i, "fileName"));
            found.sort();
            const same = found.length === tree.names.length
                && found.every((name, i) => name === tree.names[i]);
            if (same)
                return;
            tree.names = found;
        }

        property Timer settleTimer: Timer {
            id: settleTimer
            interval: 100
            onTriggered: tree.rescan()
        }

        // A root that is not there reads as empty rather than as a fault. The
        // home one is made at startup by [Directories], so by the time anybody
        // has something to drop into it there is a directory to watch.
        property FolderListModel listing: FolderListModel {
            id: listing
            folder: `file://${tree.base}`
            showDirs: true
            showFiles: false
            showDotAndDotDot: false
            sortField: FolderListModel.Name
            onCountChanged: settleTimer.restart()
            onStatusChanged: if (status === FolderListModel.Ready) settleTimer.restart()
        }
    }

    property Tree homeTree: Tree { base: root.homeRoot }
    property Tree systemTree: Tree { base: root.systemRoot }

    /**
     * Every directory found, home first, as { base, name }.
     *
     * The pair rather than the name alone, because the name no longer says where
     * the directory is and two of them can share it.
     */
    readonly property var directories: {
        const out = [];
        for (const name of root.homeTree.names)
            out.push({ base: root.homeRoot, name: name });
        for (const name of root.systemTree.names)
            out.push({ base: root.systemRoot, name: name });
        return out;
    }

    property Instantiator slots: Instantiator {
        model: root.directories
        delegate: Slot {
            required property var modelData
            base: modelData.base
            directory: modelData.name
        }
    }

    /**
     * One row per installed plugin: what it is, whether it runs, why it does not,
     * and the settings it declared.
     *
     * The model already held all of this and nothing could ask it, which is why
     * turning a plugin off meant editing the config by hand and configuring one
     * meant editing a second file by hand.
     */
    readonly property list<var> entries: {
        const rows = [];
        for (let i = 0; i < (root.slots?.count ?? 0); i++) {
            const slot = root.slots.objectAt(i);
            if (!slot)
                continue;
            rows.push({
                id: slot.pluginId,
                name: slot.name.length > 0 ? slot.name : (slot.pluginId.length > 0 ? slot.pluginId : slot.directory),
                directory: slot.directory,
                problem: root.problems[slot.place] ?? "",
                running: slot.instance !== null,
                schema: slot.configSchema,
                settings: slot.settings?.values ?? null
            });
        }
        return rows;
    }

    /**
     * The settings pages installed plugins contribute, ready for a page catalogue.
     *
     * Read off the manifests rather than off the built instances, so this answers
     * in the settings window too -- that process reads manifests but deliberately
     * hosts nothing, and a page whose existence depended on the plugin running
     * would be missing from the one window that has to show it.
     *
     * `component` names the page and nothing else. It used to be a path from the
     * shell root, which made it both the identity the window compares to know
     * which page is open and the thing its loader loads. A plugin in the home
     * root has no path from the shell root at all, so the two are separate: this
     * is the identity, and `url` is what gets loaded.
     *
     * A plugin that is switched off contributes nothing: its page would open on
     * a service that is not running.
     */
    readonly property list<var> pageEntries: {
        const pages = [];
        for (let i = 0; i < (root.slots?.count ?? 0); i++) {
            const slot = root.slots.objectAt(i);
            if (!slot || slot.pluginId.length === 0 || slot.settingsPage === null)
                continue;
            if (root.isDisabled(slot.pluginId))
                continue;
            const page = slot.settingsPage;
            pages.push({
                key: page.key,
                name: page.name,
                icon: page.icon,
                description: page.description,
                keywords: page.keywords,
                group: page.group,
                order: page.order,
                component: `plugin:${slot.pluginId}:${page.key}`,
                url: `file://${slot.place}/${page.entry}`,
                pluginId: slot.pluginId
            });
        }
        // By declared order, then by name, so two plugins that both say nothing
        // about where they go still land in a stable sequence rather than in
        // whatever order the directories were read.
        pages.sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
        return pages;
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
            const problem = root.problems[slot.place] ?? "";
            const id = slot.pluginId.length > 0 ? slot.pluginId : "-";
            const state = slot.instance !== null ? "running" : (problem.length > 0 ? "broken" : (root.isDisabled(id) ? "off" : "pending"));
            rows.push([id, state, slot.place, problem]);
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
