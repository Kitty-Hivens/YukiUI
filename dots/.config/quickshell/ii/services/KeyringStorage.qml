pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * For storing sensitive data in the keyring.
 * Use this for small data only, since it stores a JSON of the contents directly and doesn't use a database.
 */
Singleton {
    id: root

    signal dataChanged()

    property bool loaded: false
    /**
     * Set when the stored value came back and could not be read.
     *
     * Retrying does not help, since the bytes will not change on their own, and
     * writing over them would destroy whatever is really there. The shell stops
     * asking and refuses to save instead.
     */
    property bool unreadable: false
    property var keyringData: ({})
    
    /**
     * What the entry is filed under. Constant, and deliberately not translated.
     *
     * These are what the keyring matches an item by, so they are identity, not
     * writing. Translated, the explanation changed with the interface language:
     * storing then no longer replaced the existing item, it added a second one
     * beside it, and a lookup by application alone came back with whichever of
     * the two it felt like -- so a set of keys could simply stop being there.
     *
     * The sentence a person reads is the label below, which is free to be
     * translated because nothing matches on it.
     */
    readonly property var properties: {
        "application": "illogical-impulse",
        "explanation": "For storing API keys and other sensitive information",
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("illogical-impulse")

    /**
     * Stores one value, and reports whether it could be stored at all.
     *
     * Refused until the stored contents are known. Everything the shell keeps
     * lives in a single entry, so merging a field into an empty object and
     * saving that does not add a key -- it replaces every other secret with the
     * one being set.
     */
    function setNestedField(path, value) {
        if (!root.loaded) {
            console.error("[KeyringStorage] not saving: the stored data has not been read yet");
            return false;
        }
        if (!root.keyringData) root.keyringData = {};
        let keys = path;
        let obj = root.keyringData;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Set the value at the innermost key
        obj[keys[keys.length - 1]] = value;

        // Reassign each parent object from the bottom up to trigger change notifications
        for (let i = keys.length - 2; i >= 0; --i) {
            let parent = parents[i];
            let key = keys[i];
            // Shallow clone to change object identity (spread replaced with Object.assign)
            parent[key] = Object.assign({}, parent[key]);
        }

        // Finally, reassign root.keyringData to trigger top-level change
        root.keyringData = Object.assign({}, root.keyringData);

        saveKeyringData();
        return true;
    }

    function fetchKeyringData() {
        // Asking again cannot turn unreadable contents into readable ones, and
        // every caller asks on a schedule of its own.
        if (root.unreadable)
            return;
        getData.running = true;
    }

    function saveKeyringData() {
        saveData.stdinEnabled = true;
        saveData.running = true;
    }

    /** Reported when the store did not happen, so a caller can stop claiming it did. */
    signal saveFailed(string reason)

    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + keyringLabel,
            ...propertiesAsArgs,
        ]
        stderr: StdioCollector { id: saveDataErr }
        onRunningChanged: {
            if (saveData.running) {
                saveData.write(JSON.stringify(root.keyringData));
                root.dataChanged()
                stdinEnabled = false // End input stream
            }
        }
        // Nothing used to look at this. A store that failed -- no secret-tool,
        // a keyring that locked in between, a refusal from the service -- was
        // indistinguishable from one that worked, and the sidebar went on to
        // announce a key it had not saved anywhere.
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            const reason = saveDataErr.text.trim();
            console.error("[KeyringStorage] could not store, exit", exitCode, reason);
            root.saveFailed(reason);
        }
    }

    Process {
        id: getData
        command: [ // We need to use echo for a newline so splitparser does parse
            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,
        ]
        stdout: StdioCollector {
            id: keyringDataOutputCollector
        }
        // The exit code says which of the three answers this is, so the decision
        // is made here rather than by guessing from the text. What was collected
        // is already in hand: a stream ends before its process is reported gone.
        onExited: (exitCode, exitStatus) => {
            // A locked keyring still holds everything and reads once it is
            // unlocked, so nothing is concluded and nothing is marked loaded.
            if (exitCode === 2)
                return;
            if (exitCode !== 0) {
                // Nothing stored yet. The entry appears when the first value is
                // saved, rather than being created empty from here.
                root.keyringData = {};
                root.loaded = true;
                return;
            }
            try {
                root.keyringData = JSON.parse(keyringDataOutputCollector.text);
                root.loaded = true;
            } catch (e) {
                // Left exactly as it is. This is the only copy of every key the
                // shell holds, and a read it cannot make sense of is not a
                // reason to replace it with an empty one.
                console.error("[KeyringStorage] stored data could not be read, leaving it untouched:", e);
                root.unreadable = true;
            }
        }
    }
    
}
