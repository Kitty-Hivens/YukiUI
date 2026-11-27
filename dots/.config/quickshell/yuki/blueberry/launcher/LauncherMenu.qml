import QtQuick
import Quickshell

import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// What a right click on an application in the launcher offers: the actions its
// desktop entry declares, starting it, pinning it to the launcher and to the
// dock, and its page in the settings, also as the way to take it off. Drawn in the launcher's own window over everything in it, so it is
// cut by neither the grid nor the panel. A press anywhere else in the window
// closes it, and so does Escape.
Item {
    id: root

    property var entry: null
    property bool shown: false
    /** Where it opens, in this item's terms. */
    property point at: Qt.point(0, 0)
    /** Takes the keyboard back once the menu is gone. */
    property Item returnFocus: null

    readonly property string entryId: root.entry?.id ?? ""
    /** The name the dock goes by: the class its windows carry, which the entry says when it differs from its id. */
    readonly property string dockId: (root.entry?.startupClass ?? "").length > 0 ? root.entry.startupClass : root.entryId
    readonly property bool pinnedHere: (Config.options.launcher.pinnedApps ?? []).includes(root.entryId)
    readonly property bool pinnedOnDock: TaskbarApps.isPinned(root.dockId) || TaskbarApps.isPinned(root.entryId)

    readonly property var items: {
        const entry = root.entry;
        if (!entry)
            return [];
        const list = [];
        for (const action of entry.actions ?? [])
            list.push({ key: `action:${action.name}`, text: action.name, glyph: "", away: true, run: () => AppLaunch.runAction(entry, action) });
        if (list.length > 0)
            list.push({ key: "separator:actions", separator: true });
        list.push({ key: "open", text: Translation.tr("Open"), glyph: "open_in_new", away: true, run: () => AppLaunch.run(entry) });
        list.push({ key: "separator:pins", separator: true });
        list.push({
            key: "pinHere",
            text: root.pinnedHere ? Translation.tr("Unpin from the launcher") : Translation.tr("Pin to the launcher"),
            glyph: root.pinnedHere ? "keep_off" : "keep",
            run: () => root.togglePinHere()
        });
        list.push({
            key: "pinDock",
            text: root.pinnedOnDock ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock"),
            glyph: root.pinnedOnDock ? "keep_off" : "keep",
            run: () => root.togglePinOnDock()
        });
        list.push({ key: "separator:settings", separator: true });
        list.push({ key: "settings", text: Translation.tr("App settings"), glyph: "settings", away: true, run: () => Surfaces.open("settings", `app:${root.entryId}`) });
        // Asked on the application's own page, which says what goes with it.
        list.push({ key: "uninstall", text: Translation.tr("Uninstall"), glyph: "delete", destructive: true, away: true, run: () => Surfaces.open("settings", `app:${root.entryId}|uninstall`) });
        return list;
    }

    function popup(entry, at: point) {
        root.entry = entry;
        root.at = at;
        root.shown = true;
        keys.current = null;
        keys.forceActiveFocus();
    }

    function dismiss() {
        if (!root.shown)
            return;
        root.shown = false;
        root.returnFocus?.forceActiveFocus();
    }

    function run(item) {
        root.dismiss();
        if (item.away)
            ExStates.launcherOpen = false;
        item.run();
    }

    function togglePinHere() {
        const pins = Config.options.launcher.pinnedApps ?? [];
        Config.options.launcher.pinnedApps = root.pinnedHere ? pins.filter(pin => pin !== root.entryId) : pins.concat([root.entryId]);
    }

    function togglePinOnDock() {
        // Unpinned by whichever name it was pinned under, pinned by the dock's.
        if (TaskbarApps.isPinned(root.entryId))
            TaskbarApps.togglePin(root.entryId);
        else
            TaskbarApps.togglePin(root.dockId);
    }

    onShownChanged: ExStates.launcherMenuOpen = root.shown
    Component.onDestruction: {
        if (root.shown)
            ExStates.launcherMenuOpen = false;
    }

    property real openness: root.shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: ExLooks.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ExLooks.motion.decelerate
        }
    }

    visible: root.openness > 0
    z: 100

    // A press beside the menu closes it and goes no further.
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        acceptedButtons: Qt.AllButtons
        onPressed: root.dismiss()
    }

    ExMenu {
        id: plane

        implicitWidth: ExLooks.sizes.menuWidth
        // Opened at the pointer, kept inside the window.
        x: Math.max(ExLooks.spacing.s, Math.min(root.at.x, root.width - width - ExLooks.spacing.s))
        y: root.at.y + height + ExLooks.spacing.s <= root.height ? root.at.y : Math.max(ExLooks.spacing.s, root.at.y - height)
        opacity: Math.min(1, root.openness * 1.8)
        scale: 0.94 + 0.06 * root.openness
        transformOrigin: Item.TopLeft
        enabled: root.shown

        Repeater {
            model: ScriptModel {
                values: root.items
                objectProp: "key"
            }

            Loader {
                id: slot

                required property var modelData

                width: parent?.width ?? 0
                sourceComponent: slot.modelData.separator ? separator : item

                Component {
                    id: separator
                    ExMenuSeparator {}
                }

                Component {
                    id: item
                    ExMenuItem {
                        text: slot.modelData.text
                        glyph: slot.modelData.glyph
                        destructive: slot.modelData.destructive ?? false
                        onClicked: root.run(slot.modelData)
                    }
                }
            }
        }
    }

    ExMenuKeys {
        id: keys
        menu: plane
        onCloseRequested: root.dismiss()
    }
}
