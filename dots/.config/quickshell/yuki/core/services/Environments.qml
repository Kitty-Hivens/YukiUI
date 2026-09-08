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
 * The environments installed, and the one that is up.
 *
 * An environment is a part rather than an addition: panels, the rules the
 * compositor runs under, the keys, and a look, taken together. So this differs
 * from the plugin host in the way that matters -- every plugin found is built,
 * because each one adds something, while exactly one environment is built,
 * because the others are alternatives to it rather than companions.
 *
 * Enumerated from manifests, so an environment that is not installed is simply
 * not offered. Nothing here names one.
 */
Singleton {
    id: root

    /** The one API generation this host knows how to build. */
    readonly property int apiVersion: 1

    /**
     * Where desktops are looked for, and which copy wins when both hold one.
     *
     * Two roots, for the reason given in [Plugins]: the tree the shell is read
     * from belongs to whatever installed it, and is no place to keep something a
     * person added. A copy in the home root shadows one that ships with the
     * shell.
     *
     * What a desktop kept here may import is narrower than it looks. Its entry
     * is loaded by url, which works anywhere on disk and keeps `qs.*`, so it can
     * import whatever the shell's own tree already registers. What it cannot do
     * is have its own subdirectories reached by module name: only the scanner
     * writes those, and it walks the static import graph from the shell root. A
     * desktop kept here addresses its own files by relative url.
     */
    readonly property string systemRoot: FileUtils.trimFileProtocol(Quickshell.shellPath("environments"))
    readonly property string homeRoot: Directories.userEnvironments

    /** id -> { id, name, url, home }. Replaced rather than mutated, so bindings hear it. */
    property var manifests: Object.create(null)

    readonly property list<string> ids: Object.keys(root.manifests).sort()

    // Woken from shell.qml: the scan has to have started before the config is
    // read, or the first answer about what is installed would be "nothing".
    function load() {}

    function has(id) {
        return Object.prototype.hasOwnProperty.call(root.manifests, id);
    }

    function nameOf(id) {
        return root.manifests[id]?.name ?? id;
    }

    /**
     * Installed and turned off are different answers.
     *
     * `ids` is what is on disk. `offeredIds` is what a person is invited to
     * switch to. Keeping them apart is what lets an environment ship with the
     * shell without being pushed at anyone, and lets it be turned back on
     * without reinstalling anything.
     */
    readonly property list<string> disabledIds: Config.ready ? Config.options.disabledEnvironments : []

    readonly property list<string> offeredIds: root.ids.filter(id => root.disabledIds.indexOf(id) === -1)

    function isOffered(id) {
        return root.offeredIds.indexOf(id) !== -1;
    }

    /**
     * What to come up on when the config asks for something that is not here.
     *
     * Without this an unknown name in the config activated no environment at
     * all and the shell came up empty, recoverable only by editing the file by
     * hand. Takes the first offered by name, so the answer does not depend on
     * the order a scan finished and this file goes on naming no environment in
     * particular. Falls back to the installed list when everything is turned
     * off, because an empty desktop is worse than an unwanted one.
     */
    readonly property string fallbackId: {
        const usable = id => root.failedIds.indexOf(id) === -1;
        const offered = root.offeredIds.filter(usable);
        const pool = offered.length > 0 ? offered : root.ids.filter(usable);
        return pool.length > 0 ? pool[0] : "";
    }

    /**
     * Environments whose entry would not build, and why, keyed by id.
     *
     * Being installed was taken as being usable, so a manifest naming an entry
     * with a syntax error, or naming a file that is not there, left the desktop
     * empty for good: the mount failed, nothing else was tried, and the name in
     * the config went on resolving to the same broken environment. One that
     * fails is set aside so the fallback can reach past it, and a shell with a
     * broken environment comes up on another rather than on nothing.
     *
     * The reason is kept rather than only logged. It went to the journal and
     * nowhere else, so a desktop that came up wearing a different face could
     * answer that it was broken but not what was wrong with it, and the one
     * question worth answering needed the log to answer.
     */
    property var failures: Object.create(null)

    readonly property list<string> failedIds: Object.keys(root.failures)

    /**
     * Why a directory is not on offer, keyed by its full path.
     *
     * By the path and not by the name: the same name can appear under both
     * roots, and somebody's own copy of a desktop is exactly that case.
     */
    property var problems: Object.create(null)

    function reject(place, reason) {
        console.warn(`[Environments] ${place}: ${reason}`);
        const next = Object.assign(Object.create(null), root.problems);
        next[place] = reason;
        root.problems = next;
    }

    function clearProblem(place) {
        if (root.problems[place] === undefined)
            return;
        const next = Object.assign(Object.create(null), root.problems);
        delete next[place];
        root.problems = next;
    }

    function noteFailure(id, reason) {
        console.warn(`[Environments] ${id}: ${reason}`);
        if (root.failures[id] !== undefined)
            return;
        const next = Object.assign(Object.create(null), root.failures);
        next[id] = reason;
        root.failures = next;
    }

    /**
     * Asked for by name, answered by what is installed -- not by what is
     * offered. Turning an environment off hides it from the switcher; it does
     * not evict someone who is already using it.
     */
    function resolve(id) {
        return (root.has(id) && root.failedIds.indexOf(id) === -1) ? id : root.fallbackId;
    }

    /** Which one should be up. Driven by the shell, which paces the swap. */
    property string activeId: ""
    property var active: null

    onActiveIdChanged: root.remount()

    function remount() {
        if (root.active) {
            root.active.destroy();
            root.active = null;
        }
        const id = root.activeId;
        if (id.length === 0)
            return;
        const manifest = root.manifests[id];
        if (!manifest) {
            console.warn(`[Environments] ${id} is not installed, nothing mounted`);
            return;
        }
        const component = Qt.createComponent(manifest.url, Component.PreferSynchronous);
        if (component.status !== Component.Ready) {
            root.noteFailure(id, component.status === Component.Error ? component.errorString() : "the entry did not finish building");
            return;
        }
        const object = component.createObject(root);
        if (!object) {
            root.noteFailure(id, "the entry built nothing");
            return;
        }
        root.active = object;
        console.log(`[Environments] ${id} mounted`);
    }

    /**
     * What the config asked for, when that is not what came up. Empty otherwise.
     *
     * `resolve` answers with the fallback rather than the name in the config,
     * which is what keeps a broken or uninstalled environment from leaving the
     * desktop empty. It answered in silence: the desktop changed face, the
     * reason sat in the journal, and working out what had happened was left to
     * whoever was sitting in front of it.
     */
    readonly property string substitutedId: {
        if (!Config.ready || root.activeId.length === 0)
            return "";
        const asked = Config.options.panelFamily;
        return asked !== root.activeId ? asked : "";
    }

    function whySubstituted(id) {
        if (root.failures[id] !== undefined)
            return root.failures[id];
        if (!root.has(id))
            return Translation.tr("it is not installed");
        return Translation.tr("it is unavailable");
    }

    /**
     * Said once per substitution, and late on purpose.
     *
     * The notification daemon is this shell, and the surface that draws a
     * notification belongs to an environment. Announcing at the moment of the
     * swap would be speaking while the only thing that could listen is still
     * being built.
     *
     * Cleared when the substitution ends, so an environment that breaks again
     * after being repaired is announced again rather than once for good.
     */
    property string announcedId: ""

    onSubstitutedIdChanged: {
        if (root.substitutedId.length === 0) {
            announcer.stop();
            root.announcedId = "";
            return;
        }
        announcer.restart();
    }

    Timer {
        id: announcer

        interval: 3000
        onTriggered: {
            const asked = root.substitutedId;
            if (asked.length === 0 || asked === root.announcedId)
                return;
            root.announcedId = asked;
            Quickshell.execDetached(["notify-send", Translation.tr("Desktop changed"), Translation.tr("%1 did not start (%2), so %3 is running instead").arg(root.nameOf(asked)).arg(root.whySubstituted(asked)).arg(root.nameOf(root.activeId)), "-a", "Shell"]);
        }
    }

    /** Whether the entry was taken. Refused only in favour of a home copy. */
    function register(manifest) {
        const held = root.manifests[manifest.id];
        // Which manifest was read first is not a decision anybody made, so the
        // root decides instead.
        if (held !== undefined && held.url !== manifest.url && held.home && !manifest.home)
            return false;
        const next = Object.assign(Object.create(null), root.manifests);
        next[manifest.id] = manifest;
        root.manifests = next;
        return true;
    }

    /** Removes the entry only if it is still the one this directory registered. */
    function unregister(id, url) {
        if (root.manifests[id]?.url !== url)
            return;
        const next = Object.assign(Object.create(null), root.manifests);
        delete next[id];
        root.manifests = next;
        Qt.callLater(root.reconsider);
    }

    /**
     * Offers every shadowed directory the id it was refused.
     *
     * Reached when an entry is removed, which is what happens when the directory
     * that held the id goes away. Without it, deleting your own copy of a
     * desktop left the one shipped with the shell unreachable until the next
     * reload.
     */
    function reconsider() {
        for (const instantiator of [root.homeSlots, root.systemSlots])
            for (let i = 0; i < (instantiator?.count ?? 0); i++) {
                const slot = instantiator.objectAt(i);
                if (slot?.shadowed)
                    slot.read(slot.manifestText);
            }
    }

    /** One directory under one of the roots, however far it gets. */
    component Slot: QtObject {
        id: slot

        required property string base
        required property string directory
        /** Both roots can hold a directory of the same name, so this is what
         *  names one of them. */
        readonly property string place: `${slot.base}/${slot.directory}`
        readonly property bool fromHome: slot.base === root.homeRoot
        /** Kept so a directory refused in favour of a home copy can be offered
         *  its id back without the manifest being read a second time. */
        property string manifestText: ""
        property bool shadowed: false
        property string environmentId: ""
        property string entryUrl: ""

        function read(text) {
            slot.manifestText = text;
            slot.shadowed = false;
            root.clearProblem(slot.place);
            let manifest;
            try {
                manifest = JSON.parse(text);
            } catch (error) {
                root.reject(slot.place, "the manifest is not JSON");
                return;
            }
            if (!Plugins.usableId(manifest?.id)) {
                root.reject(slot.place, `"${manifest?.id}" cannot be an id -- letters, digits, dashes and underscores only`);
                return;
            }
            if (!Plugins.usableEntry(manifest?.entry)) {
                root.reject(slot.place, `"${manifest?.entry}" cannot be an entry -- a path inside this directory, with no ".." in it`);
                return;
            }
            if (!manifest?.id || !manifest?.entry) {
                root.reject(slot.place, "the manifest names no id or no entry");
                return;
            }
            if (manifest.apiVersion !== root.apiVersion) {
                root.reject(slot.place, `it wants API ${manifest.apiVersion}, this host speaks ${root.apiVersion}`);
                return;
            }
            slot.environmentId = manifest.id;
            slot.entryUrl = `file://${slot.place}/${manifest.entry}`;
            const taken = root.register({
                id: manifest.id,
                name: manifest.name ?? manifest.id,
                url: slot.entryUrl,
                home: slot.fromHome
            });
            if (!taken) {
                slot.shadowed = true;
                root.reject(slot.place, `"${manifest.id}" is taken by ${root.manifests[manifest.id].url}`);
            }
        }

        property FileView manifestFile: FileView {
            path: `${slot.place}/manifest.json`
            onLoaded: slot.read(text())
            onLoadFailed: root.reject(slot.place, "there is no manifest here")
        }

        Component.onDestruction: {
            // Said first, and for a directory that never got an id as well: a
            // reason otherwise outlives the directory it was about, and this
            // one's report reads the problem list directly.
            root.clearProblem(slot.place);
            if (slot.environmentId.length > 0)
                root.unregister(slot.environmentId, slot.entryUrl);
        }
    }

    component Listing: FolderListModel {
        required property string base
        folder: `file://${base}`
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    property Instantiator homeSlots: Instantiator {
        model: Listing { base: root.homeRoot }
        delegate: Slot {
            required property string fileName
            base: root.homeRoot
            directory: fileName
        }
    }

    property Instantiator systemSlots: Instantiator {
        model: Listing { base: root.systemRoot }
        delegate: Slot {
            required property string fileName
            base: root.systemRoot
            directory: fileName
        }
    }

    /** What is installed, which one is up, and what is wrong with the rest. */
    function report(): string {
        const rows = root.ids.map(id => {
            const failure = root.failures[id];
            const state = id === root.activeId ? "active"
                : (failure !== undefined ? "broken"
                : (root.isOffered(id) ? "offered" : "off"));
            return [id, state, failure !== undefined ? `${root.nameOf(id)}  -- ${failure}` : root.nameOf(id)];
        });
        for (const place of Object.keys(root.problems))
            rows.push(["-", "broken", `${place}  -- ${root.problems[place]}`]);
        if (rows.length === 0)
            return "no environments installed";
        const width = Math.max(...rows.map(row => row[0].length));
        return rows.map(row => `${row[0].padEnd(width)}  ${row[1].padEnd(7)}  ${row[2]}`).join("\n");
    }

    IpcHandler {
        target: "environments"

        function list(): string {
            return root.report();
        }
        function use(id: string): string {
            if (!Config.ready)
                return "the config has not been read yet, try again";
            if (!root.has(id))
                return `no environment here is called "${id}"`;
            if (root.failedIds.indexOf(id) !== -1)
                return `${id} did not build, so it is not offered -- see the journal for why`;
            // Turned back on if it was off: asking for it by name is asking for it.
            Config.options.disabledEnvironments = Config.options.disabledEnvironments.filter(other => other !== id);
            Config.options.panelFamily = id;
            return `switching to ${id}`;
        }
    }
}
