import qs.core.services
import qs.core
import qs.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.ii.sidebarRight.quickToggles.androidStyle
import qs.common

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // Sizes
    implicitHeight: (editMode ? contentItem.implicitHeight : usedRows.implicitHeight) + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        // This is the wrong calculation, but it looks correct in reality???
        // (theoretically spacing should be multiplied by 1 column less)
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Toggles
    // What the shell brings, followed by what the installed plugins offer. The
    // second half is why this is not a constant: a plugin that is not there
    // must not leave a name in the pool that nothing can draw.
    readonly property list<string> builtInToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang"]
    // Deduplicated: a plugin is free to take an id a built-in toggle already uses,
    // and the name landing in this pool twice puts two identical tiles in the row
    // of unused ones -- which the row cannot tell apart.
    readonly property list<string> availableToggleTypes: root.builtInToggleTypes
        .concat(Plugins.quickToggleIds.filter(id => root.builtInToggleTypes.indexOf(id) === -1))
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    // Read through a filter rather than straight: an entry with no type is dead
    // weight, and the same type twice is a state the panel cannot draw -- rows are
    // keyed by type, and two rows keyed alike is undefined. A config that already
    // holds one (the older edit code could write it) is drawn as the one tile it
    // was meant to be.
    readonly property list<var> toggles: {
        if (!Config.ready)
            return [];
        const seen = [];
        return Config.options.sidebar.quickToggles.android.toggles.filter(toggle => {
            if (!toggle?.type || seen.indexOf(toggle.type) !== -1)
                return false;
            seen.push(toggle.type);
            return true;
        });
    }
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0; // Total cols taken in current row
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            // An empty row is never opened: a first tile wider than the panel used
            // to push one, which drew as a gap above everything else.
            if (row.length > 0 && totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12
        
        Column {
            id: usedRows
            spacing: root.spacing

            Repeater {
                id: usedRowsRepeater
                model: ScriptModel {
                    values: Array(root.toggleRows.length)
                }
                delegate: ButtonGroup {
                    id: toggleRow
                    required property int index
                    property var modelData: root.toggleRows[index]
                    spacing: root.spacing

                    Repeater {
                        // Type names rather than the entries themselves. Reading an
                        // entry builds a fresh object every time, so no two reads are
                        // the same object and the model could not tell one tile from
                        // another: it rewrote rows in place instead of moving them,
                        // and a delegate built for one kind of toggle stayed to draw
                        // the next -- the tile that was removed still on screen, its
                        // neighbour gone, and a click landing on neither.
                        model: ScriptModel {
                            values: (toggleRow?.modelData ?? []).map(toggle => toggle.type)
                        }
                        delegate: AndroidToggleDelegateChooser {
                            editMode: root.editMode
                            baseCellWidth: root.baseCellWidth
                            baseCellHeight: root.baseCellHeight
                            spacing: root.spacing
                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenBluetoothDialog: root.openBluetoothDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                            onOpenGameModeDialog: root.openGameModeDialog()
                        }
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: (unusedToggleRow?.modelData ?? []).map(toggle => toggle.type)
                            }
                            delegate: AndroidToggleDelegateChooser {
                                editMode: root.editMode
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
                    }
                }
            }
        }
    }
}
