import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland

import qs.core
import qs.core.launcherEntry
import qs.core.services
import qs.blueberry
import qs.blueberry.dockMove
import qs.blueberry.input
import qs.blueberry.looks
import qs.blueberry.notificationCenter

// The dock: launcher, the applications of the workspace on screen, and the
// status block at its far end. One per screen, on whichever edge the config
// names, in one of three ways of standing there.
Scope {
    id: root

    property list<var> docks: []

    /**
     * Whether a tray icon is in view rather than under the arrow, read off the
     * list itself. The tray service answers only for icons it is showing, and
     * a passive icon it filters out would read as hidden either way.
     */
    function trayShown(id: string): bool {
        const listed = Config.options.tray.pinnedItems.includes(id);
        return Config.options.tray.invertPinnedItems ? !listed : listed;
    }

    LauncherEntryWatcher {
        id: launcherEntries
    }

    // Blur behind the dock, which the compositor draws by a rule this
    // environment keeps. Asked for as the shell starts, when the settings
    // change, and after every reload of the compositor, which drops it. A
    // pixel no more opaque than the threshold is left unblurred: the shadow
    // round a floating dock stays clear, and the plate is always above it.
    readonly property bool blurWanted: Config.options.blueberry.dock.blur
    readonly property real plateAlpha: ExLooks.colors.dockPlate.a
    onBlurWantedChanged: blurApply.restart()
    onPlateAlphaChanged: blurApply.restart()
    Component.onCompleted: blurApply.restart()
    Timer {
        id: blurApply
        interval: 150
        onTriggered: {
            const threshold = Math.min(0.3, root.plateAlpha * 0.6).toFixed(3);
            Quickshell.execDetached(["hyprctl", "eval", `if YUKI_SET_DOCK_BLUR then YUKI_SET_DOCK_BLUR(${root.blurWanted}, ${threshold}) end`]);
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                blurApply.restart();
        }
    }

    // A tray icon being carried, as on Windows: along the tray to move it, onto
    // the chevron or among the icons it hides to keep it out of the way, and
    // back. Held here rather than by one dock, since the pointer can take it
    // from one screen's dock to another's.
    property string carriedId: ""
    /** Where it would land: the screen, "dock" or "overflow", and the place among what is there. */
    property string dropScreen: ""
    property string dropPlace: ""
    property int dropIndex: -1
    /** Which of the two said so, the tray or the popup, so only that one takes it back. */
    property string dropVia: ""

    /** Tray icons in the order they were put in, ones never moved after in the order they came. */
    function trayOrdered(items): var {
        const order = Config.options.blueberry.dock.trayOrder;
        const rank = id => {
            const at = order.indexOf(id);
            return at === -1 ? order.length : at;
        };
        return [...items].sort((a, b) => rank(a.id) - rank(b.id));
    }

    /**
     * What a place shows: { key, item, state }, with the carried icon held open
     * where it would land, and faded where it was taken from until it lands.
     * Its place there is kept rather than closed: the tray stands against the
     * status block, so closing it moved the chevron, and the popup hanging off
     * the chevron, out from under the pointer carrying it there. Kept rather
     * than left out as well since that icon is the source of the drag.
     */
    function trayEntries(items, screen: string, place: string): var {
        const entries = root.trayOrdered(items).map(item => ({ key: item.id, item: item, state: "" }));
        const carried = root.carriedId;
        if (carried.length === 0)
            return entries;
        const own = entries.findIndex(entry => entry.key === carried);
        if (root.dropScreen === screen && root.dropPlace === place) {
            const item = own >= 0 ? entries[own].item : SystemTray.items.values.find(candidate => candidate.id === carried);
            if (!item)
                return entries;
            const rest = entries.filter(entry => entry.key !== carried);
            rest.splice(Math.max(0, Math.min(root.dropIndex, rest.length)), 0, { key: carried, item: item, state: "gap" });
            return rest;
        }
        if (own >= 0)
            entries[own] = Object.assign({}, entries[own], { state: "carried" });
        return entries;
    }

    function carryOver(screen: string, place: string, index: int, via: string) {
        root.dropScreen = screen;
        root.dropPlace = place;
        root.dropIndex = index;
        root.dropVia = via;
    }

    function carryAway(screen: string, via: string) {
        if (root.dropScreen !== screen || root.dropVia !== via)
            return;
        root.dropScreen = "";
        root.dropPlace = "";
        root.dropIndex = -1;
        root.dropVia = "";
    }

    function carryEnded() {
        const drop = root.pendingDrop;
        root.pendingDrop = null;
        dropFallback.stop();
        if (drop)
            root.commitDrop(drop.id, drop.place, drop.index);
        root.carriedId = "";
        root.dropScreen = "";
        root.dropPlace = "";
        root.dropIndex = -1;
        root.dropVia = "";
    }

    /**
     * A drop waiting for the drag to finish. Carried out at once, it took the
     * icon out of the list it was carried from, and with it the very item the
     * drag came from, which then never said the drag was over: the icon stayed
     * held open in its new place, invisible.
     */
    property var pendingDrop: null

    function trayDrop(place: string, index: int) {
        if (root.carriedId.length === 0)
            return;
        root.pendingDrop = { id: root.carriedId, place: place, index: index };
        dropFallback.restart();
    }

    // For a drag whose source went away all the same, its program quitting say.
    Timer {
        id: dropFallback
        interval: 1000
        onTriggered: root.carryEnded()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.carriedId.length > 0
        onTriggered: {
            if (!SystemTray.items.values.some(item => item.id === root.carriedId))
                root.carryEnded();
        }
    }

    /** Puts an icon in a place, shown in the dock or kept out of the way, before what stands at that index there. */
    function commitDrop(id: string, place: string, index: int) {
        const shown = place === "dock";
        const present = SystemTray.items.values.map(item => item.id);
        const order = root.trayOrdered(SystemTray.items.values).map(item => item.id).filter(other => other !== id);
        const there = root.trayOrdered(shown ? TrayService.pinnedItems : TrayService.unpinnedItems).map(item => item.id).filter(other => other !== id);
        if (index < there.length)
            order.splice(order.indexOf(there[index]), 0, id);
        else if (there.length > 0)
            order.splice(order.indexOf(there[there.length - 1]) + 1, 0, id);
        else
            order.push(id);
        // Programs not running now keep their places for when they come back.
        const absent = Config.options.blueberry.dock.trayOrder.filter(other => other !== id && !present.includes(other));
        Config.options.blueberry.dock.trayOrder = [...order, ...absent];
        root.setTrayShown(id, shown);
    }

    function setTrayShown(id: string, shown: bool) {
        if (root.trayShown(id) !== shown)
            TrayService.togglePin(id);
    }

    // Moving to another edge, in steps: "capture" while the tray and status
    // block are pictured, "prepare" while the overlays come up showing the
    // dock as it stands, "switch" while the dock, hidden, takes its new place,
    // "recapture" while they are pictured there, "fly" while the overlays
    // carry it there, "reveal" while the dock fades back in under them. Empty
    // when nothing is moving.
    property string phase: ""
    /** The edge a drag would put the dock on, or empty when there is no drag. */
    property string moveTarget: ""
    property var shapesBefore: ({})
    property var shapesAfter: ({})
    property string pendingEdge: ""
    property var readyScreens: []
    property var landedScreens: []
    readonly property var edges: ["bottom", "top", "left", "right"]

    /** Takes the dock to another edge, showing it on its way. False when it cannot go now. */
    function moveTo(edge: string): bool {
        if (root.phase !== "" || !root.edges.includes(edge) || edge === Config.options.blueberry.dock.edge)
            return false;
        // Asked for over IPC, a flyout could be open, placed against the
        // edge the dock is leaving.
        for (const dock of root.docks)
            dock.closePopups(null);
        root.pendingEdge = edge;
        root.shapesBefore = ({});
        root.shapesAfter = ({});
        root.readyScreens = [];
        root.landedScreens = [];
        // The tray and the status block are pictured first, to be shown
        // fading where they stood while the plate closes.
        root.phase = "capture";
        root.captureAll(() => {
            const shapes = {};
            for (const dock of root.docks)
                shapes[dock.modelData.name] = dock.shape();
            root.shapesBefore = shapes;
            root.phase = "prepare";
            prepareTimeout.restart();
        });
        return true;
    }

    /** Pictures every dock's tray and status block, then goes on, however many answer. */
    property var afterCapture: null

    function captureAll(then) {
        let left = root.docks.length;
        let finished = false;
        const finish = () => {
            if (finished)
                return;
            finished = true;
            captureTimeout.stop();
            root.afterCapture = null;
            then();
        };
        root.afterCapture = finish;
        captureTimeout.restart();
        if (left === 0) {
            finish();
            return;
        }
        for (const dock of root.docks)
            dock.grabParts(() => {
                if (--left === 0)
                    finish();
            });
    }

    function overlayReady(screen: string) {
        if (root.phase !== "prepare")
            return;
        if (!root.readyScreens.includes(screen))
            root.readyScreens = [...root.readyScreens, screen];
        if (root.readyScreens.length >= root.docks.length)
            root.switchEdge();
    }

    function switchEdge() {
        prepareTimeout.stop();
        root.phase = "switch";
        Config.options.blueberry.dock.edge = root.pendingEdge;
        settle.seen = false;
        settle.attempts = 0;
        settle.restart();
    }

    function flightDone(screen: string) {
        if (root.phase !== "fly")
            return;
        if (!root.landedScreens.includes(screen))
            root.landedScreens = [...root.landedScreens, screen];
        if (root.landedScreens.length >= root.docks.length)
            root.reveal();
    }

    function reveal() {
        flightTimeout.stop();
        root.phase = "reveal";
        revealTimer.restart();
    }

    // Each step waits on the one before, and none of them waits for ever.
    Timer {
        id: captureTimeout
        interval: 250
        onTriggered: root.afterCapture?.()
    }
    Timer {
        id: prepareTimeout
        interval: 400
        onTriggered: {
            if (root.phase === "prepare")
                root.switchEdge();
        }
    }
    Timer {
        id: settle

        property bool seen: false
        property int attempts: 0

        // Until the compositor has given every dock its new shape, and one
        // more tick for its contents to be laid out in it.
        interval: 60
        onTriggered: {
            const settled = root.docks.every(dock => dock.settled());
            if ((!settled || !settle.seen) && ++settle.attempts < 12) {
                settle.seen = settled;
                settle.restart();
                return;
            }
            // Pictured again as they stand on the new edge, to show up as the
            // plate opens there.
            root.phase = "recapture";
            root.captureAll(() => {
                const shapes = {};
                for (const dock of root.docks)
                    shapes[dock.modelData.name] = dock.shape();
                root.shapesAfter = shapes;
                root.phase = "fly";
                flightTimeout.restart();
            });
        }
    }
    Timer {
        id: flightTimeout
        interval: 2000
        onTriggered: root.reveal()
    }
    // However a step goes wrong, a move does not stay under way for good: the
    // dock stayed hidden behind its overlay, and every later move was refused.
    Timer {
        interval: 8000
        running: root.phase !== ""
        onTriggered: {
            console.warn("[ExDock] a move to another edge never finished, letting go of it");
            captureTimeout.stop();
            prepareTimeout.stop();
            settle.stop();
            flightTimeout.stop();
            root.afterCapture = null;
            root.phase = "";
            root.shapesBefore = ({});
            root.shapesAfter = ({});
        }
    }
    Timer {
        id: revealTimer
        interval: ExLooks.motion.normal + 40
        onTriggered: {
            root.phase = "";
            root.shapesBefore = ({});
            root.shapesAfter = ({});
        }
    }

    // On every screen, or only on the main one. Hyprland names no main
    // screen, so the one furthest left, and of those the highest, stands in
    // for it, as for the desktop icons.
    readonly property var dockScreens: Config.options.blueberry.dock.screens === "main"
        ? [...Quickshell.screens].sort((a, b) => a.x - b.x || a.y - b.y).slice(0, 1)
        : Quickshell.screens

    Variants {
        model: root.dockScreens

        PanelWindow {
            id: window

            required property var modelData

            readonly property string edge: Config.options.blueberry.dock.edge
            readonly property string dockStyle: Config.options.blueberry.dock.style
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property bool detached: dockStyle !== "attached"
            readonly property bool island: dockStyle === "island"
            readonly property bool centered: Config.options.blueberry.dock.alignment !== "start"
            readonly property real gap: detached ? ExLooks.dock.floatingGap : 0
            // Room for the shadow of a dock that stands off the edge, which falls
            // towards the middle of the screen.
            readonly property real shadowRoom: detached ? 16 : 0
            readonly property real thickness: ExLooks.dock.thickness + gap + shadowRoom
            readonly property int workspaceId: Hyprland.monitorFor(window.screen)?.activeWorkspace?.id ?? -1
            readonly property int monitorId: Hyprland.monitorFor(window.screen)?.id ?? -1

            /**
             * Whether a window has a button on this dock: one on the workspace
             * on screen, or any at all, or with a dock on each screen any on
             * this screen, as the settings say.
             */
            readonly property var appList: TaskbarApps.appsMatching(toplevel => window.showsWindow(toplevel))

            // Windows' "combine buttons and hide labels". Combined, one icon per
            // application. Otherwise a labelled button per window, an
            // application with none keeping its icon, and "when full" goes
            // back to icons once the labelled buttons no longer fit. Down a
            // side there is no room for a label at all.
            readonly property string combine: Config.options.blueberry.dock.combine
            readonly property real labelledLength: {
                let length = Config.options.blueberry.dock.launcherButton ? ExLooks.dock.cell : 0;
                let count = Config.options.blueberry.dock.launcherButton ? 1 : 0;
                for (const app of window.appList) {
                    const windows = Math.max(1, app.windows.length);
                    length += app.windows.length > 0 ? windows * ExLooks.dock.labelledWidth : ExLooks.dock.cell;
                    count += windows;
                }
                return length + Math.max(0, count - 1) * ExLooks.dock.spacing;
            }
            readonly property bool labelled: !window.vertical && window.combine !== "always"
                && (window.combine === "never" || window.labelledLength <= dock.screenLength - dock.endLength - 2 * dock.padding)

            /** One per button, keyed so a button keeps its place as the list changes. */
            readonly property var buttons: {
                const list = [];
                for (const app of window.appList) {
                    if (!window.labelled || app.windows.length === 0) {
                        list.push(Object.assign({ key: app.appId }, app));
                        continue;
                    }
                    for (const toplevel of app.windows)
                        list.push(Object.assign({}, app, { key: `${app.appId}|${TaskbarApps.addressOf(toplevel)}`, window: toplevel, windows: [toplevel] }));
                }
                return list;
            }

            function showsWindow(toplevel): bool {
                const options = Config.options.blueberry.dock;
                if (options.windowsFrom !== "all")
                    return TaskbarApps.workspaceOf(toplevel) === window.workspaceId;
                if (options.screens !== "main" && options.appsOn === "own" && Quickshell.screens.length > 1)
                    return TaskbarApps.monitorOf(toplevel) === window.monitorId;
                return true;
            }
            // A window in real fullscreen, not merely maximised, on the
            // workspace this dock shows.
            readonly property bool underFullscreen: HyprlandData.windowList.some(win => win.workspace.id === window.workspaceId && (win.fullscreen & 2) !== 0)

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "quickshell:dock"
            // Over the applications, as the Windows taskbar and the bars of
            // the other environments are. Under them, the shadow of a window
            // standing over the dock fell on it, so the dock was darker with
            // a window there and darker still with that window focused. The
            // menus of a Wayland application are kept off the room it keeps.
            // Under a fullscreen window the compositor hides it itself, and it
            // keeps nothing from showing that window on its own. Moved to the
            // layer below by hand, it never came back: the move back takes a
            // commit, and a surface covered by a fullscreen window draws none.
            WlrLayershell.layer: WlrLayer.Top
            onUnderFullscreenChanged: {
                if (window.underFullscreen)
                    window.closePopups(null);
            }
            // Hidden on its own, it keeps no room from the windows.
            exclusiveZone: window.autoHide ? 0 : ExLooks.dock.thickness + gap

            // Out of the way until the pointer reaches the edge, as Windows'
            // "automatically hide the taskbar". It stays while the pointer is
            // over it, while anything it opened is open, while the launcher is
            // up and while it is being moved, and goes a moment after.
            readonly property bool autoHide: Config.options.blueberry.dock.autoHide
            readonly property bool anyPopupOpen: [windowList, appMenu, trayMenu, trayOverflow, quickSettings, notificationCenter, layoutMenu, dockMenu, statusMenu, quickLinks, captureMenu, clipboard].some(popup => popup.open)
            readonly property bool keepShown: !window.autoHide || dockHover.hovered || stripHover.hovered || window.anyPopupOpen
                || ExStates.launcherOpen || root.phase !== "" || dragArea.Drag.active || window.holdingKeys || root.carriedId.length > 0
            property bool revealed: !window.autoHide
            /** From in place (0) to out of sight past the edge (1). */
            property real hidden: window.revealed ? 0 : 1
            Behavior on hidden {
                NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }
            onKeepShownChanged: {
                if (window.keepShown) {
                    autoHideTimer.stop();
                    window.revealed = true;
                } else {
                    autoHideTimer.restart();
                }
            }
            onAutoHideChanged: {
                if (!window.autoHide)
                    window.revealed = true;
                else if (!window.keepShown)
                    autoHideTimer.restart();
            }
            Timer {
                id: autoHideTimer
                interval: 700
                onTriggered: {
                    if (!window.keepShown)
                        window.revealed = false;
                }
            }

            // What the pointer touches while the dock is away: the last
            // pixels of the screen along the edge. Shown, the same strip also
            // covers what lies between a floating dock and the edge, so going
            // past the dock to the edge does not count as leaving it.
            Item {
                id: edgeStrip
                readonly property real depth: window.revealed ? window.gap + 2 : 2
                x: window.edge === "right" ? window.width - width : 0
                y: window.edge === "bottom" ? window.height - height : 0
                width: window.vertical ? depth : window.width
                height: window.vertical ? window.height : depth

                HoverHandler {
                    id: stripHover
                }
            }

            // The keyboard, while quick settings has a password field up, and
            // while the clipboard history is open.
            //
            // A popup that takes no grab gets no keys of its own, and taking a
            // grab would let the compositor shut it on the first click outside.
            // So the dock's layer asks for them: outright for a moment, which
            // hands them over at once, then on demand, which keeps them and
            // still lets a click elsewhere take them away and count as a click
            // outside. Held exclusively for longer, a click outside was
            // reported as one on the dock and the flyout never closed. What
            // arrives at the dock is handed to the field. A click into the
            // field gives the flyout's own window the keys directly.
            readonly property Item keyTarget: quickSettings.keyTarget ?? clipboard.keyTarget
            property bool holdingKeys: false
            property bool seizingKeys: false
            WlrLayershell.keyboardFocus: !window.holdingKeys ? WlrKeyboardFocus.None
                : window.seizingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
            onKeyTargetChanged: {
                if (window.keyTarget) {
                    keysLetGo.stop();
                    keysHandOver.stop();
                    window.holdingKeys = true;
                    // Taken outright only with the press-report plugin. Without
                    // it the flyout holds a focus grab, which a layer turning
                    // exclusive clears, and quick settings closed as its
                    // password field came up.
                    window.seizingKeys = PointerPress.available;
                    if (window.seizingKeys)
                        keysSeize.restart();
                } else if (window.holdingKeys) {
                    // The same care as the launcher's: letting go with the
                    // pointer over the dock can bring back a window on a
                    // workspace out of sight.
                    if (FocusReturn.beforeLettingGo())
                        keysLetGo.restart();
                    else
                        window.holdingKeys = false;
                }
            }
            Timer {
                id: keysSeize
                interval: 60
                onTriggered: window.seizingKeys = false
            }
            Timer {
                id: keysLetGo
                interval: 80
                onTriggered: {
                    window.holdingKeys = false;
                    keysHandOver.restart();
                }
            }
            Timer {
                id: keysHandOver
                interval: 60
                onTriggered: FocusReturn.handOver()
            }
            Item {
                focus: true
                Keys.forwardTo: window.keyTarget ? [window.keyTarget] : []
            }
            anchors {
                top: window.edge !== "bottom"
                bottom: window.edge !== "top"
                left: window.edge !== "right"
                right: window.edge !== "left"
            }
            implicitWidth: window.vertical ? window.thickness : 0
            implicitHeight: window.vertical ? 0 : window.thickness
            // Only the dock itself takes the pointer. The shadow around a floating
            // one, and the empty stretch beside an island, let clicks through.
            mask: Region {
                item: window.autoHide && !window.revealed ? edgeStrip : dock

                Region {
                    item: window.autoHide ? edgeStrip : null
                }
            }

            Component.onCompleted: {
                root.docks = [...root.docks, window];
                ExStates.dockWindows = [...ExStates.dockWindows, window];
            }
            Component.onDestruction: {
                // Gone mid-drag, the drop that ends the move never comes, and
                // the overlay's catcher on every screen would take every click.
                if (dragArea.Drag.active)
                    root.moveTarget = "";
                root.docks = root.docks.filter(other => other !== window);
                ExStates.dockWindows = ExStates.dockWindows.filter(other => other !== window);
            }

            /** Clicks the application at a place on the dock, counted from one. */
            function activateAt(place: int): bool {
                const button = tasks.itemAt(place - 1);
                if (!button)
                    return false;
                button.activate();
                return true;
            }

            /** Opens the menu of the tray icon at a place, counted from one. */
            function trayMenuAt(place: int): bool {
                const icon = tray.iconAt(place);
                if (!icon?.item?.hasMenu)
                    return false;
                icon.menuRequested(icon);
                return true;
            }

            function toggleQuickSettings() {
                closePopups(quickSettings);
                quickSettings.toggle(status.statusButton);
            }

            function toggleLayoutMenu() {
                closePopups(layoutMenu);
                layoutMenu.toggle(status.layoutButton);
            }

            function toggleCaptureMenu() {
                closePopups(captureMenu);
                captureMenu.toggle(status.captureButton);
            }

            function toggleNotificationCenter() {
                closePopups(notificationCenter);
                notificationCenter.toggle(status.clockButton);
            }

            function toggleClipboard() {
                closePopups(clipboard);
                clipboard.toggle(clipboardPoint);
            }

            function closeClipboard() {
                clipboard.open = false;
            }

            /** One flyout at a time: everything but the one about to open is shut. */
            function closePopups(except) {
                for (const popup of [windowList, appMenu, trayMenu, trayOverflow, quickSettings, notificationCenter, layoutMenu, dockMenu, statusMenu, quickLinks, captureMenu, clipboard])
                    if (popup !== except)
                        popup.open = false;
            }

            /** Where an item of the dock sits, in the coordinates of this dock's screen. */
            function place(item: Item): var {
                // Both corners, since the applications can be drawn smaller
                // than they are laid out.
                const inWindow = item.mapToItem(null, 0, 0);
                const farCorner = item.mapToItem(null, item.width, item.height);
                const originX = window.edge === "right" ? window.screen.width - window.width : 0;
                const originY = window.edge === "bottom" ? window.screen.height - window.height : 0;
                return { x: originX + inWindow.x, y: originY + inWindow.y, w: farCorner.x - inWindow.x, h: farCorner.y - inWindow.y };
            }

            /**
             * Where the button of an application sits, in the coordinates of
             * this dock's screen, or null when it has none here. What a
             * window flies into when it is minimised.
             */
            function buttonRect(appId: string, address: string): var {
                // The button of that very window when windows have their own,
                // else the application's.
                let found = null;
                for (let i = 0; i < tasks.count; i++) {
                    const button = tasks.itemAt(i);
                    if (!button || button.entry?.appId !== appId)
                        continue;
                    if (button.soleWindow && TaskbarApps.addressOf(button.soleWindow) === address)
                        return window.place(button.iconItem);
                    found = found ?? button;
                }
                return found ? window.place(found.labelled ? found.iconItem : found) : null;
            }

            /** The dock's plate, its icons, and pictures of its tray and status block, where they stand. */
            function shape(): var {
                const items = launcherButton.visible ? [Object.assign({ key: "launcher", kind: "launcher" }, window.place(launcherButton))] : [];
                for (let i = 0; i < tasks.count; i++) {
                    const button = tasks.itemAt(i);
                    if (button?.entry)
                        // A labelled button is drawn as its icon on the way.
                        items.push(Object.assign({ key: button.key, kind: "app", icon: AppSearch.iconFor(button.entry.appId) }, window.place(button.labelled ? button.iconItem : button)));
                }
                const pictures = [];
                for (const [key, item] of [["tray", tray], ["status", status]]) {
                    const grab = window.partGrabs[key];
                    if (grab && item.visible && item.width > 0)
                        pictures.push(Object.assign({ key: key, url: grab.url }, window.place(item)));
                }
                return {
                    plate: Object.assign(window.place(dock), { radius: dock.radius, elevation: dock.elevation, bordered: dock.bordered }),
                    items: items,
                    pictures: pictures
                };
            }

            /** The latest pictures of the tray and the status block, kept alive while shown. */
            property var partGrabs: ({})

            function grabParts(done) {
                const parts = [["tray", tray], ["status", status]].filter(part => part[1].visible && part[1].width > 0 && part[1].height > 0);
                const grabs = {};
                let left = parts.length;
                const settle = () => {
                    if (--left === 0) {
                        window.partGrabs = grabs;
                        done();
                    }
                };
                if (left === 0) {
                    window.partGrabs = grabs;
                    done();
                    return;
                }
                for (const part of parts) {
                    const asked = part[1].grabToImage(result => {
                        grabs[part[0]] = result;
                        settle();
                    });
                    if (!asked)
                        settle();
                }
            }

            /** Whether the compositor has given the window the shape its edge asks for. */
            function settled(): bool {
                return window.vertical ? Math.abs(window.width - window.thickness) < 1 && window.height > window.width
                    : Math.abs(window.height - window.thickness) < 1 && window.width > window.height;
            }

            DockMoveOverlay {
                screenModel: window.modelData
                mover: root
                islandLength: dock.contentLength
            }

            /** Opens the menu of the application at a place on the dock, counted from one. */
            function menuAt(place: int): bool {
                const button = tasks.itemAt(place - 1);
                if (!button)
                    return false;
                button.menuRequested();
                return true;
            }

            ExSurface {
                id: dock

                readonly property real padding: ExLooks.spacing.s
                readonly property real contentLength: (window.vertical
                        ? apps.implicitHeight + tray.implicitHeight + status.implicitHeight
                        : apps.implicitWidth + tray.implicitWidth + status.implicitWidth) + 4 * padding
                    + (showDesktop.visible ? showDesktop.breadth : 0)
                // An island grows with what it holds, up to the screen's length.
                readonly property real screenLength: (window.vertical ? window.height : window.width) - 2 * window.gap
                readonly property real length: window.island ? Math.min(contentLength, screenLength) : screenLength
                // What the far end takes, the tray, the status block and the
                // corner button, measured from the dock's end to the tray's start.
                readonly property real endLength: padding + (showDesktop.visible ? showDesktop.breadth : 0)
                    + (window.vertical ? status.implicitHeight + tray.implicitHeight : status.implicitWidth + tray.implicitWidth) + padding / 2
                // The stretch the applications may take, a padding clear of the
                // tray. With more of them than fit they are drawn smaller
                // rather than running under the tray, or off an island's end.
                readonly property real appsRoom: length - endLength - 2 * padding
                readonly property real appsLength: window.vertical ? apps.implicitHeight : apps.implicitWidth
                readonly property real appsScale: appsLength > appsRoom && appsRoom > 0 ? appsRoom / appsLength : 1
                readonly property real along: window.island && !window.centered ? window.gap
                    : ((window.vertical ? window.height : window.width) - length) / 2

                width: window.vertical ? ExLooks.dock.thickness : length
                height: window.vertical ? length : ExLooks.dock.thickness
                // Slid past the edge when hidden, its shadow with it.
                readonly property real away: window.hidden * window.thickness
                x: window.vertical ? (window.edge === "left" ? window.gap - away : window.width - width - window.gap + away) : along
                y: window.vertical ? along : (window.edge === "top" ? window.gap - away : window.height - height - window.gap + away)
                radius: window.detached ? ExLooks.dock.floatingRadius : 0
                elevation: window.detached ? 1 : 0
                color: ExLooks.colors.dockPlate
                // Against the screen edge a hairline all round let the wallpaper
                // show through along the edges the dock touches: the fill stops
                // inside the border. There it is drawn along the inner edge only.
                bordered: window.detached

                Rectangle {
                    visible: !window.detached
                    z: 1
                    color: ExLooks.colors.hairline
                    x: window.edge === "left" ? parent.width - 1 : 0
                    y: window.edge === "top" ? parent.height - 1 : 0
                    width: window.vertical ? 1 : parent.width
                    height: window.vertical ? parent.height : 1
                }
                // On the plate, which holds everything on the dock, rather than
                // on an item beside it: the status block, the tray and the
                // buttons of the windows take the hover themselves, and an item
                // under them, not around them, was no longer hovered, so the
                // dock slid away from under a pointer resting on the clock.
                HoverHandler {
                    id: dockHover
                }

                // Out of sight while it is being carried to another edge, and
                // back at once under the overlay, which then fades off it: the
                // look goes from the one to the other with no thin moment
                // between, which fading both at once gave.
                opacity: root.phase === "switch" || root.phase === "recapture" || root.phase === "fly" ? 0 : 1

                // A long press on the dock itself, not on anything in it,
                // picks it up, and it goes to the screen edge it is dropped
                // nearest.
                //
                // Carried as a drag-and-drop, the one grab Wayland gives a
                // client that follows the pointer across other surfaces. Held
                // by the pressed button alone, the drag lost the pointer as
                // soon as it left the dock whenever nothing had the keyboard,
                // since only then does Hyprland keep a held button's motion on
                // the surface it was pressed on. The overlay of the move takes
                // the drop, and says which edge is nearest while it goes.
                MouseArea {
                    id: dragArea

                    anchors.fill: parent
                    z: -1
                    pressAndHoldInterval: 450
                    // A right click opens the dock's own menu where it landed.
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        // A click on the dock's empty stretch closes what is open, as
                        // one on an empty stretch of the Windows taskbar does.
                        if (event.button !== Qt.RightButton) {
                            window.closePopups(null);
                            return;
                        }
                        menuPoint.x = event.x;
                        menuPoint.y = event.y;
                        window.closePopups(dockMenu);
                        // Elsewhere on the dock while it is open, the menu
                        // comes out again there rather than closing.
                        dockMenu.open = false;
                        dockMenu.toggle(menuPoint);
                    }

                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.MoveAction
                    Drag.mimeData: ({ "application/x-yuki-dock": window.modelData.name })
                    Drag.onDragStarted: root.moveTarget = window.edge
                    // A drop the overlay did not take, Escape say, leaves the dock where it is.
                    Drag.onDragFinished: dropAction => {
                        dragArea.Drag.active = false;
                        if (dropAction !== Qt.MoveAction)
                            root.moveTarget = "";
                    }

                    onPressAndHold: {
                        if (root.phase !== "" || !(dragArea.pressedButtons & Qt.LeftButton))
                            return;
                        window.closePopups(null);
                        // Begun while the press is still the dock's. The
                        // overlay comes up once it has.
                        dragArea.Drag.active = true;
                    }
                }

                GridLayout {
                    id: apps

                    columns: window.vertical ? 1 : 256
                    rowSpacing: ExLooks.dock.spacing
                    columnSpacing: ExLooks.dock.spacing
                    scale: dock.appsScale
                    transformOrigin: Item.TopLeft

                    // Gathered in the middle of the dock or from its start. An island
                    // is only as long as what it holds, so it has no middle to speak of.
                    // From the middle they move towards the start once the middle
                    // would put them under the tray, as Windows does.
                    readonly property real drawnLength: dock.appsLength * dock.appsScale
                    readonly property real drawnBreadth: (window.vertical ? width : height) * dock.appsScale
                    readonly property real startOffset: (window.island || !window.centered) ? dock.padding
                        : Math.max(dock.padding, Math.min((dock.length - drawnLength) / 2, dock.length - dock.endLength - dock.padding - drawnLength))
                    x: window.vertical ? (parent.width - drawnBreadth) / 2 : startOffset
                    y: window.vertical ? startOffset : (parent.height - drawnBreadth) / 2

                    ExButton {
                        id: launcherButton

                        visible: Config.options.blueberry.dock.launcherButton
                        kind: "flat"
                        implicitWidth: ExLooks.dock.cell
                        implicitHeight: ExLooks.dock.cell
                        onClicked: {
                            window.closePopups(null);
                            ExStates.launcherOpen = !ExStates.launcherOpen;
                        }
                        // A right click opens the quick links, as one on Start does.
                        onRightClicked: {
                            ExStates.launcherOpen = false;
                            window.closePopups(quickLinks);
                            quickLinks.toggle(launcherButton);
                        }

                        ExGlyph {
                            anchors.centerIn: parent
                            text: "apps"
                            size: ExLooks.dock.launcherGlyph
                            color: ExLooks.colors.accent
                        }
                    }

                    Repeater {
                        id: tasks

                        // The keys alone, which compare by value, and each button
                        // finds what it stands for by its key. The buttons are made
                        // anew on every pass, and given those, a list whose first
                        // row matched by key but not by object was rewritten row by
                        // row from there, keys unchecked: with an application gone,
                        // the button that had been it, and a menu open on it, went
                        // on as the next one along.
                        model: ScriptModel {
                            values: window.buttons.map(button => button.key)
                        }

                        DockTaskButton {
                            required property string modelData
                            readonly property string key: modelData
                            // Null for the moment between its key going and the button going.
                            readonly property var button: window.buttons.find(candidate => candidate.key === modelData) ?? null
                            entry: button?.entry ?? null
                            soleWindow: button?.window ?? null
                            reach: Math.max(0, (ExLooks.dock.thickness - ExLooks.dock.cell) / 2)
                            status: launcherEntries.stateFor(button?.appId ?? "")
                            workspaceId: window.workspaceId
                            showsWindow: toplevel => window.showsWindow(toplevel)
                            edge: window.edge
                            onGroupRequested: {
                                window.closePopups(windowList);
                                windowList.toggle(this);
                            }
                            onMenuRequested: {
                                window.closePopups(appMenu);
                                appMenu.toggle(this);
                            }
                        }
                    }
                }

                DockTray {
                    id: tray

                    edge: window.edge
                    entries: root.trayEntries(TrayService.pinnedItems, window.modelData.name, "dock")
                    chevronShown: TrayService.unpinnedItems.length > 0 || root.carriedId.length > 0
                    x: window.vertical ? (parent.width - width) / 2 : status.x - width - dock.padding / 2
                    y: window.vertical ? status.y - height - dock.padding / 2 : (parent.height - height) / 2
                    onMenuRequested: (item, button) => {
                        window.closePopups(trayMenu);
                        trayMenu.openFor(item, button);
                    }
                    onOverflowRequested: button => {
                        window.closePopups(trayOverflow);
                        trayOverflow.toggle(button);
                    }
                    onChevronHeld: button => {
                        if (trayOverflow.open || TrayService.unpinnedItems.length === 0)
                            return;
                        window.closePopups(trayOverflow);
                        trayOverflow.toggle(button);
                    }
                    onCarryStarted: id => {
                        window.closePopups(trayOverflow);
                        root.carriedId = id;
                    }
                    onCarryFinished: root.carryEnded()
                    // Over the chevron it goes with the hidden ones, at their end.
                    onCarriedOver: (place, onChevron) => root.carryOver(window.modelData.name, onChevron ? "overflow" : "dock", onChevron ? 1000 : place, "tray")
                    onCarriedAway: root.carryAway(window.modelData.name, "tray")
                    onDroppedAt: (place, onChevron) => root.trayDrop(onChevron ? "overflow" : "dock", onChevron ? 1000 : place)
                }

                DockStatus {
                    id: status

                    vertical: window.vertical
                    crossSize: window.vertical ? dock.width : dock.height
                    onClicked: window.toggleQuickSettings()
                    onClockClicked: window.toggleNotificationCenter()
                    onLayoutClicked: window.toggleLayoutMenu()
                    onCaptureClicked: window.toggleCaptureMenu()
                    onMenuRequested: (kind, at) => {
                        window.closePopups(statusMenu);
                        statusMenu.openFor(kind, at);
                    }
                    x: window.vertical ? (parent.width - width) / 2 : parent.width - width - dock.padding - (showDesktop.visible ? showDesktop.breadth : 0)
                    y: window.vertical ? parent.height - height - dock.padding - (showDesktop.visible ? showDesktop.breadth : 0) : (parent.height - height) / 2
                }

                // The far corner: minimises everything on the workspace, and a
                // second click brings it back. Set off from the clock by a
                // short rule, the way Windows draws it.
                AbstractButton {
                    id: showDesktop

                    ExPrimaryOnly {
                        z: 1
                    }

                    readonly property real breadth: 12

                    visible: Config.options.blueberry.dock.showDesktop
                    width: window.vertical ? parent.width : showDesktop.breadth
                    height: window.vertical ? showDesktop.breadth : parent.height
                    x: window.vertical ? 0 : parent.width - width
                    y: window.vertical ? parent.height - height : 0
                    hoverEnabled: true
                    onClicked: {
                        window.closePopups(null);
                        Minimize.toggleDesktop(window.workspaceId);
                    }

                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 3
                            color: "transparent"

                            ExStateLayer {
                                ink: ExLooks.colors.text
                                hovered: showDesktop.hovered
                                pressed: showDesktop.down
                            }
                        }
                        Rectangle {
                            color: ExLooks.colors.border
                            width: window.vertical ? parent.width * 0.5 : 1
                            height: window.vertical ? 1 : parent.height * 0.5
                            x: window.vertical ? (parent.width - width) / 2 : 0
                            y: window.vertical ? 0 : (parent.height - height) / 2
                        }
                    }
                }
            }

            // Where a right click on the dock landed, for its menu to come out of.
            Item {
                id: menuPoint
                parent: dock
                width: 1
                height: 1
            }

            // The middle of the dock, where the clipboard history comes out:
            // the same place every time, whatever the pointer is doing.
            Item {
                id: clipboardPoint
                parent: dock
                x: dock.width / 2
                y: dock.height / 2
                width: 1
                height: 1
            }

            DockClipboard {
                id: clipboard
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockMenu {
                id: dockMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
                workspaceId: window.workspaceId
            }

            DockStatusMenu {
                id: statusMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockQuickLinks {
                id: quickLinks
                dockWindow: window
                dockSurface: dock
                edge: window.edge
                workspaceId: window.workspaceId
            }

            DockWindowList {
                id: windowList
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockAppMenu {
                id: appMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockTrayMenu {
                id: trayMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            ExLayoutMenu {
                id: layoutMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
                layouts: status.layouts
            }

            DockCaptureMenu {
                id: captureMenu
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            ExNotificationCenter {
                id: notificationCenter
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockQuickSettings {
                id: quickSettings
                dockWindow: window
                dockSurface: dock
                edge: window.edge
            }

            DockTrayOverflow {
                id: trayOverflow
                dockWindow: window
                dockSurface: dock
                edge: window.edge
                entries: root.trayEntries(TrayService.unpinnedItems, window.modelData.name, "overflow")
                onCarryStarted: id => root.carriedId = id
                onCarryFinished: root.carryEnded()
                onCarriedOver: place => root.carryOver(window.modelData.name, "overflow", place, "overflow")
                onCarriedAway: root.carryAway(window.modelData.name, "overflow")
                onDroppedAt: place => root.trayDrop("overflow", place)
                // Opened where the hidden icons came out, since the icon asked
                // for lives in a popup that closes to make room.
                onMenuRequested: item => {
                    const chevron = trayOverflow.opener;
                    trayOverflow.open = false;
                    trayMenu.openFor(item, chevron);
                }
            }
        }
    }

    /**
     * Opens or closes quick settings, the notifications or the clipboard
     * history on the dock of the focused screen, and says why not when it
     * cannot.
     */
    function toggleFlyout(which: string): string {
        const screen = Hyprland.focusedMonitor?.name ?? "";
        const dock = root.docks.find(candidate => candidate.screen?.name === screen);
        if (!dock)
            return "no dock on the focused screen";
        // Under a fullscreen window the dock sits behind it, and a flyout
        // opened there would not be seen, while one with a field would take
        // the keyboard from the game.
        if (dock.underFullscreen)
            return "a fullscreen window is in front of the dock";
        if (which === "quickSettings")
            dock.toggleQuickSettings();
        else if (which === "clipboard")
            dock.toggleClipboard();
        else
            dock.toggleNotificationCenter();
        return "ok";
    }

    // Win+V, through the history, which first notes the window to paste into.
    Connections {
        target: ExClipboardHistory
        function onToggleRequested() {
            root.toggleFlyout("clipboard");
        }
        function onCloseRequested() {
            for (const dock of root.docks)
                dock.closeClipboard();
        }
    }

    // For a touchpad gesture or a key bound to them.
    GlobalShortcut {
        name: "dockQuickSettings"
        description: "Opens or closes quick settings"
        onPressed: root.toggleFlyout("quickSettings")
    }
    GlobalShortcut {
        name: "dockNotifications"
        description: "Opens or closes the notifications and the calendar"
        onPressed: root.toggleFlyout("notifications")
    }

    IpcHandler {
        target: "dock"

        /** The same as clicking the application at that place on the dock of the focused screen. */
        function activate(place: int): string {
            const screen = Hyprland.focusedMonitor?.name ?? "";
            const dock = root.docks.find(candidate => candidate.screen?.name === screen);
            if (!dock)
                return "no dock on the focused screen";
            return dock.activateAt(place) ? "ok" : `nothing at place ${place}`;
        }

        /** Opens the menu of the tray icon at that place on the dock of the focused screen. */
        function trayMenu(place: int): string {
            const screen = Hyprland.focusedMonitor?.name ?? "";
            const dock = root.docks.find(candidate => candidate.screen?.name === screen);
            if (!dock)
                return "no dock on the focused screen";
            // Under a fullscreen window the dock sits behind it, and a flyout
            // opened there would not be seen, while one with a field would
            // take the keyboard from the game.
            if (dock.underFullscreen)
                return "a fullscreen window is in front of the dock";
            return dock.trayMenuAt(place) ? "ok" : `no menu at place ${place}`;
        }

        /** Opens or closes quick settings on the dock of the focused screen. */
        function quickSettings(): string {
            return root.toggleFlyout("quickSettings");
        }

        /** Opens or closes the notifications and the calendar on the dock of the focused screen. */
        function notifications(): string {
            return root.toggleFlyout("notifications");
        }

        /**
         * The tray's icons for the settings window, which must not watch the
         * tray itself: a second watcher could take the role over from the
         * shell. JSON, one object per icon: id, title, the icon theme name
         * when the icon is one, and whether it is shown in the dock rather
         * than under the arrow.
         */
        function trayItems(): string {
            return JSON.stringify(SystemTray.items.values.map(item => ({
                id: item.id,
                // The program's name, not its tooltip, which can be the song playing.
                title: item.title || item.tooltipTitle || item.id,
                icon: (/^image:\/\/icon\/([^?]+)/.exec(item.icon ?? "") ?? [])[1] ?? "",
                shown: root.trayShown(item.id)
            })));
        }

        /** Shows a tray icon in the dock, or puts it under the arrow. */
        function setTrayShown(id: string, shown: bool): string {
            root.setTrayShown(id, shown);
            return "ok";
        }

        /** Takes the dock to another edge, as dragging it there does: bottom, top, left or right. */
        function move(edge: string): string {
            return root.moveTo(edge) ? "ok" : "cannot move there now";
        }

        /** The same as a right click there. */
        function menu(place: int): string {
            const screen = Hyprland.focusedMonitor?.name ?? "";
            const dock = root.docks.find(candidate => candidate.screen?.name === screen);
            if (!dock)
                return "no dock on the focused screen";
            // Under a fullscreen window the dock sits behind it, and a flyout
            // opened there would not be seen, while one with a field would
            // take the keyboard from the game.
            if (dock.underFullscreen)
                return "a fullscreen window is in front of the dock";
            return dock.menuAt(place) ? "ok" : `nothing at place ${place}`;
        }
    }
}
