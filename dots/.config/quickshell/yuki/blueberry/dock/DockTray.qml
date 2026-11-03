import QtQuick
import Quickshell

import qs.blueberry.looks

// The tray, beside the status block at the far end of the dock: the icons kept
// in view, and behind a chevron the ones kept out of the way.
//
// An icon is carried with the mouse, as on Windows: along the tray to another
// place, onto the chevron or into what it opens to be kept out of the way, and
// back from there into the tray. Where it would land opens up as it goes.
Item {
    id: root

    property string edge: "bottom"
    readonly property bool vertical: edge === "left" || edge === "right"

    /** What to show, in order: { key, item, state }, state one of the ExDock tray states. */
    property var entries: []
    /** Whether the chevron is shown: something is under it, or an icon is being carried. */
    property bool chevronShown: false

    signal menuRequested(var item, Item button)
    signal overflowRequested(Item button)
    /** A carried icon was held over the chevron: what it hides is to come out. */
    signal chevronHeld(Item button)
    /** An icon of this tray was picked up. */
    signal carryStarted(string id)
    signal carryFinished(bool dropped)
    /** A carried icon is over the tray, and would land at this place, or on the chevron. */
    signal carriedOver(int place, bool onChevron)
    signal carriedAway
    signal droppedAt(int place, bool onChevron)

    readonly property real cell: 32
    readonly property real chevronLength: chevron.visible ? (root.vertical ? chevron.height : chevron.width) : 0

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    /** The icon at a place in the tray, counted from one. */
    function iconAt(place: int): Item {
        return icons.itemAt(place - 1);
    }

    Grid {
        id: row

        columns: root.vertical ? 1 : 64
        spacing: 0
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        move: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: ExLooks.motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ExLooks.motion.standard
            }
        }

        // Points the way the hidden icons will come out, away from the edge.
        ExButton {
            id: chevron

            visible: root.chevronShown
            kind: "flat"
            implicitWidth: 28
            implicitHeight: 28
            onClicked: root.overflowRequested(this)

            ExGlyph {
                anchors.centerIn: parent
                text: root.edge === "top" ? "expand_more"
                    : root.edge === "left" ? "chevron_right"
                    : root.edge === "right" ? "chevron_left"
                    : "expand_less"
                size: 18
            }
        }

        Repeater {
            id: icons

            // The keys alone, each icon finding its entry by its key, as the
            // dock's buttons do and for the same reason: the entries are made
            // anew on every pass, and the model then rewrote the rows by place,
            // so the icons never moved, they changed into one another.
            model: ScriptModel {
                values: root.entries.map(entry => entry.key)
            }

            DockTrayIcon {
                required property string modelData
                // Null for the moment between its key going and the icon going.
                readonly property var entry: root.entries.find(candidate => candidate.key === modelData) ?? null

                item: entry?.item ?? null
                carryState: entry?.state ?? ""
                onMenuRequested: button => {
                    if (entry)
                        root.menuRequested(entry.item, button);
                }
                onCarryStarted: {
                    if (entry)
                        root.carryStarted(entry.item.id);
                }
                onCarryFinished: dropped => root.carryFinished(dropped)
            }
        }
    }

    // Held over the chevron a moment, it opens what it hides.
    Timer {
        id: chevronHold
        interval: 450
        onTriggered: root.chevronHeld(chevron)
    }

    DropArea {
        id: drops

        property bool overChevron: false

        anchors.fill: parent
        keys: ["application/x-yuki-tray"]

        function placeAt(drag): var {
            const along = root.vertical ? drag.y : drag.x;
            if (along < root.chevronLength)
                return { place: -1, onChevron: true };
            return { place: Math.max(0, Math.floor((along - root.chevronLength) / root.cell + 0.5)), onChevron: false };
        }

        function follow(drag) {
            const at = placeAt(drag);
            root.carriedOver(at.place, at.onChevron);
            if (at.onChevron && !drops.overChevron)
                chevronHold.restart();
            else if (!at.onChevron)
                chevronHold.stop();
            drops.overChevron = at.onChevron;
        }

        onEntered: drag => {
            drag.accept(Qt.MoveAction);
            drops.follow(drag);
        }
        onPositionChanged: drag => drops.follow(drag)
        onExited: {
            chevronHold.stop();
            drops.overChevron = false;
            root.carriedAway();
        }
        onDropped: drop => {
            chevronHold.stop();
            drops.overChevron = false;
            drop.accept(Qt.MoveAction);
            const at = placeAt(drop);
            root.droppedAt(at.place, at.onChevron);
        }
    }
}
