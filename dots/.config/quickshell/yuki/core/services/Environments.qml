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

    readonly property string environmentPath: FileUtils.trimFileProtocol(Quickshell.shellPath("environments"))
    readonly property url environmentFolder: Qt.resolvedUrl(Quickshell.shellPath("environments"))

    /** id -> { id, name, url }. Replaced rather than mutated, so bindings hear it. */
    property var manifests: ({})

    readonly property list<string> ids: Object.keys(root.manifests).sort()

    // Woken from shell.qml: the scan has to have started before the config is
    // read, or the first answer about what is installed would be "nothing".
    function load() {}

    function has(id) {
        return root.manifests[id] !== undefined;
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
        const pool = root.offeredIds.length > 0 ? root.offeredIds : root.ids;
        return pool.length > 0 ? pool[0] : "";
    }

    /**
     * Asked for by name, answered by what is installed -- not by what is
     * offered. Turning an environment off hides it from the switcher; it does
     * not evict someone who is already using it.
     */
    function resolve(id) {
        return root.has(id) ? id : root.fallbackId;
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
        const component = Qt.createComponent(manifest.url);
        if (component.status === Component.Error) {
            console.warn(`[Environments] ${id}: ${component.errorString()}`);
            return;
        }
        const object = component.createObject(root);
        if (!object) {
            console.warn(`[Environments] ${id}: the entry built nothing`);
            return;
        }
        root.active = object;
        console.log(`[Environments] ${id} mounted`);
    }

    function register(manifest) {
        const next = Object.assign({}, root.manifests);
        next[manifest.id] = manifest;
        root.manifests = next;
    }

    function unregister(id) {
        const next = Object.assign({}, root.manifests);
        delete next[id];
        root.manifests = next;
    }

    /** One directory under `environments/`, however far it gets. */
    component Slot: QtObject {
        id: slot

        required property string directory
        property string environmentId: ""

        function read(text) {
            let manifest;
            try {
                manifest = JSON.parse(text);
            } catch (error) {
                console.warn(`[Environments] ${slot.directory}: manifest is not JSON, skipped`);
                return;
            }
            if (!manifest?.id || !manifest?.entry) {
                console.warn(`[Environments] ${slot.directory}: manifest names no id or no entry, skipped`);
                return;
            }
            if (manifest.apiVersion !== root.apiVersion) {
                console.warn(`[Environments] ${manifest.id}: wants API ${manifest.apiVersion}, this host speaks ${root.apiVersion}, skipped`);
                return;
            }
            slot.environmentId = manifest.id;
            root.register({
                id: manifest.id,
                name: manifest.name ?? manifest.id,
                url: `${root.environmentFolder}/${slot.directory}/${manifest.entry}`
            });
        }

        property FileView manifestFile: FileView {
            path: `${root.environmentPath}/${slot.directory}/manifest.json`
            onLoaded: slot.read(text())
            onLoadFailed: console.warn(`[Environments] ${slot.directory}: no manifest, skipped`)
        }

        Component.onDestruction: {
            if (slot.environmentId.length > 0)
                root.unregister(slot.environmentId);
        }
    }

    property Instantiator slots: Instantiator {
        model: FolderListModel {
            folder: root.environmentFolder
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
