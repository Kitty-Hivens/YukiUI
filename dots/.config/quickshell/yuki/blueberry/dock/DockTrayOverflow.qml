import QtQuick
import Quickshell

import qs.blueberry.looks

// The tray icons kept out of the way, in a small grid over the chevron. An icon
// carried here from the tray is kept out of the way from then on, and one
// carried from here into the tray is shown there.
ExPopup {
    id: root

    /** What to show, in order: { key, item, state }, as the tray takes them. */
    property var entries: []

    signal menuRequested(var item)
    signal carryStarted(string id)
    signal carryFinished(bool dropped)
    signal carriedOver(int place)
    signal carriedAway
    signal droppedAt(int place)

    readonly property real cell: 32
    readonly property int columns: Math.min(4, Math.max(1, root.entries.length))

    padding: ExLooks.spacing.xs
    surfaceRadius: ExLooks.radius.tile

    onDismissRequested: root.open = false
    // Nothing left to show once every hidden icon has gone.
    onOpenChanged: {
        if (root.open && root.entries.length === 0)
            root.open = false;
    }
    onEntriesChanged: {
        if (root.open && root.entries.length === 0)
            root.open = false;
    }

    Item {
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight

        Grid {
            id: grid

            columns: root.columns

            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: ExLooks.motion.fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ExLooks.motion.standard
                }
            }

            Repeater {
                // By key, as the tray in the dock does.
                model: ScriptModel {
                    values: root.entries.map(entry => entry.key)
                }

                DockTrayIcon {
                    required property string modelData
                    readonly property var entry: root.entries.find(candidate => candidate.key === modelData) ?? null

                    item: entry?.item ?? null
                    carryState: entry?.state ?? ""
                    onMenuRequested: {
                        if (entry)
                            root.menuRequested(entry.item);
                    }
                    onCarryStarted: {
                        if (entry)
                            root.carryStarted(entry.item.id);
                    }
                    onCarryFinished: dropped => root.carryFinished(dropped)
                }
            }
        }

        DropArea {
            id: drops

            anchors.fill: parent
            keys: ["application/x-yuki-tray"]

            // Read across the rows, the far half of a cell counting as after it.
            function placeAt(drag): int {
                const row = Math.max(0, Math.floor(drag.y / root.cell));
                const column = Math.max(0, Math.min(root.columns, Math.floor(drag.x / root.cell + 0.5)));
                return row * root.columns + column;
            }

            onEntered: drag => {
                drag.accept(Qt.MoveAction);
                root.carriedOver(drops.placeAt(drag));
            }
            onPositionChanged: drag => root.carriedOver(drops.placeAt(drag))
            onExited: root.carriedAway()
            onDropped: drop => {
                drop.accept(Qt.MoveAction);
                root.droppedAt(drops.placeAt(drop));
            }
        }
    }
}
