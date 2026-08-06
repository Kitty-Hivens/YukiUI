pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            // Not over contents that could not be read: see onLoaded below.
            if (root.contentsUnreadable)
                return;
            persistentStatesFileView.writeAdapter()
        }
    }

    /** Empty counts as usable: that is a first run, and there is nothing to lose. */
    function contentsAreUsable(text) {
        if (!text || text.trim().length === 0)
            return true;
        try {
            const parsed = JSON.parse(text);
            // The adapter refuses anything that is not an object too, and
            // refusing it here for a different reason would come to the same
            // thing: defaults kept, then written back over the file.
            return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed);
        } catch (error) {
            return false;
        }
    }
    property bool contentsUnreadable: false

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: {
            // A read that succeeded is not contents that parsed: unusable ones
            // only warn, and the states keep what they already had, which at
            // startup is the default for every one. This file is then written
            // without anyone asking -- the instance signature goes in as soon as
            // it is ready -- so a file damaged while the machine was off is
            // replaced by defaults before anything has been clicked.
            root.contentsUnreadable = !root.contentsAreUsable(persistentStatesFileView.text());
            if (root.contentsUnreadable)
                console.error("[Persistent] the state file is not readable as JSON: keeping defaults and refusing to write over it");
            root.ready = true;
        }
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject ai: JsonObject {
                property string model: "gemini-2.5-flash"
                property real temperature: 0.5
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
            }

            property JsonObject search: JsonObject {
                property list<string> recentQueries: []
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }

            property JsonObject lock: JsonObject {
                property bool locked: false
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1650
                    property real y: 390
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1570
                    property real y: 615
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 80
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1500
                    property real y: 770
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 280
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1400
                    property real y: 42
                    property real width: 460
                    property real height: 330
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
            }
        }
    }
}
