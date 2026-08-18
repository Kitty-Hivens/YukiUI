pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.synchronizer
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar
import qs.modules.waffle.bar.tray

RowLayout {
    id: root

    property bool overflowOpen: false
    property bool dragging: false

    Layout.fillHeight: true
    spacing: 0

    BarIconButton {
        id: overflowButton

        visible: (TrayService.unpinnedItems.length > 0 || root.dragging)
        checked: root.overflowOpen

        iconName: "chevron-down"
        iconMonochrome: true
        iconRotation: (Config.options.waffles.bar.bottom ? 180 : 0) + (root.overflowOpen ? 180 : 0)
        Behavior on iconRotation {
            animation: Looks.transition.rotate.createObject(this)
        }

        onClicked: {
            root.overflowOpen = !root.overflowOpen;
        }

        TrayOverflowMenu {
            id: trayOverflowLayout
            Synchronizer on active {
                property alias source: root.overflowOpen
            }
        }

        BarToolTip {
            extraVisibleCondition: overflowButton.shouldShowTooltip
            text: Translation.tr("Show hidden icons")
        }
    }

    /// Where letting go would put the carried icon, counted in gaps: 0 before the
    /// first, 1 between the first and second, and so on. -1 when the pointer is not
    /// over the row at all.
    readonly property int dropIndex: {
        if (!TrayDragState.active || pinnedRepeater.count === 0)
            return -1;
        const first = pinnedRepeater.itemAt(0);
        if (!first)
            return -1;
        const start = first.mapToItem(null, 0, 0).x;
        const step = first.width;
        const over = (TrayDragState.pointerX - start) / step;
        if (over < -0.5 || over > pinnedRepeater.count + 0.5)
            return -1;
        return Math.max(0, Math.min(pinnedRepeater.count, Math.round(over)));
    }

    /// The pinned ids in the order they are shown, which is the order a drop rewrites.
    readonly property list<string> shownOrder: {
        const order = Config.options.tray.pinnedItems;
        return [...TrayService.pinnedItems]
            .sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id))
            .map(item => item.id);
    }

    /// Puts one id into a gap, counted among the icons on screen. Ids in the setting
    /// that have no icon at the moment keep their place at the end rather than being
    /// dropped, since they belong to applications that are simply not running.
    function moveTo(itemId, gap) {
        // The setting is a set of *hidden* items when inverted, so writing the shown
        // ones into it hides them all. Which is what happened once, to a live tray.
        if (Config.options.tray.invertPinnedItems)
            return;
        const shown = root.shownOrder;
        const from = shown.indexOf(itemId);
        if (from < 0)
            return;
        const rest = shown.filter(id => id !== itemId);
        rest.splice(gap > from ? gap - 1 : gap, 0, itemId);
        const absent = Config.options.tray.pinnedItems.filter(id => !shown.includes(id));
        Config.options.tray.pinnedItems = rest.concat(absent);
    }

    onDropIndexChanged: {
        const first = pinnedRepeater.itemAt(0);
        TrayDragState.insertX = (root.dropIndex < 0 || !first) ? -1
            : first.mapToItem(null, 0, 0).x + root.dropIndex * first.width;
    }

    Repeater {
        id: pinnedRepeater
        model: ScriptModel {
            // Ordered by the configuration's list rather than by the order the items
            // happened to register, because without that there is nothing for a drag
            // to rearrange -- the service treats the list as a set.
            values: {
                const order = Config.options.tray.pinnedItems;
                return [...TrayService.pinnedItems].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
            }
        }
        delegate: TrayButton {
            id: trayButton
            required property var modelData
            item: modelData

            /// While this one is being carried, what is left here is only the trace
            /// of where it came from -- which is what Windows leaves behind as well.
            readonly property bool carrying: TrayDragState.item === trayButton.item
            opacity: trayButton.carrying ? 0.35 : 1
            Behavior on opacity {
                animation: Looks.transition.opacity.createObject(this)
            }

            /// Whether letting go now would hide this icon. The chevron's rectangle
            /// is read in the bar window's coordinates, which is the space the drag
            /// layer shares, so no DropArea is involved and the icon is free to be
            /// anywhere on screen rather than sliding along one axis.
            readonly property bool overChevron: {
                if (!trayButton.carrying || !overflowButton.visible)
                    return false;
                const corner = overflowButton.mapToItem(null, 0, 0);
                return TrayDragState.pointerX >= corner.x
                    && TrayDragState.pointerX <= corner.x + overflowButton.width
                    && TrayDragState.pointerY >= corner.y
                    && TrayDragState.pointerY <= corner.y + overflowButton.height;
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent

                property point pressedAt
                property bool moved: false

                onPressed: event => {
                    dragArea.pressedAt = Qt.point(event.x, event.y);
                    dragArea.moved = false;
                }
                onPositionChanged: event => {
                    const far = Math.abs(event.x - dragArea.pressedAt.x) > 3
                        || Math.abs(event.y - dragArea.pressedAt.y) > 3;
                    if (!dragArea.moved && !far)
                        return;
                    const inWindow = dragArea.mapToItem(null, event.x, event.y);
                    if (!dragArea.moved) {
                        dragArea.moved = true;
                        root.dragging = true;
                        // Half the drawn icon, so it sits under the cursor rather
                        // than hanging off it.
                        TrayDragState.begin(trayButton.item, inWindow.x, inWindow.y, 8, 8);
                    } else {
                        TrayDragState.moveTo(inWindow.x, inWindow.y);
                    }
                    TrayDragState.dropAction = trayButton.overChevron ? "unpin" : "";
                }
                onReleased: {
                    if (!dragArea.moved) {
                        trayButton.click();
                    } else if (trayButton.overChevron) {
                        // Hidden first: the item leaves the model on the next line,
                        // and upstream found the shell would crash otherwise.
                        trayButton.visible = false;
                        TrayService.togglePin(trayButton.item.id);
                    } else if (root.dropIndex >= 0) {
                        root.moveTo(trayButton.item.id, root.dropIndex);
                    }
                    dragArea.moved = false;
                    TrayDragState.clear();
                    root.dragging = false;
                }
                onCanceled: {
                    dragArea.moved = false;
                    TrayDragState.clear();
                    root.dragging = false;
                }
            }
        }
    }
}
