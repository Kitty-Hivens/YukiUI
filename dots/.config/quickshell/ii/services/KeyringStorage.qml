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
    
    property var properties: {
        "application": "illogical-impulse",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("illogical-impulse")

    function setNestedField(path, value) {
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

    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + keyringLabel,
            ...propertiesAsArgs,
        ]
        onRunningChanged: {
            if (saveData.running) {
                // console.log("[KeyringStorage] Saving with command: '" + saveData.command.join("' '") + "'");
                saveData.write(JSON.stringify(root.keyringData));
                root.dataChanged()
                stdinEnabled = false // End input stream
            }
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
