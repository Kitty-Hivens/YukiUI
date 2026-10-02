pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core
import qs.core.services
import qs.experimental.looks

// Alt+Tab, as Windows does it: the windows in the order they were last used,
// the one before this one picked, Tab moving on while Alt is held and letting
// go of Alt bringing the pick up. Tapped quickly, it goes back to the window
// before without anything drawn.
//
// Alt's release is heard through a binding of the compositor's, made only while
// a switch is under way: the panel takes the keyboard only once Alt is already
// down, and a key pressed before a surface had the keyboard is not released to
// it.
Scope {
    id: root

    /** A switch is under way: Alt is held after a Tab. */
    property bool active: false
    /** The panel is on screen, a moment after the first Tab. */
    property bool shown: false
    /** The windows to pick from, each { toplevel, address, appId, title, minimized }. */
    property var items: []
    property int index: 0
    property var targetScreen: null
    property bool holdingKeys: false

    /** The windows in the order they were last used, from the workspace on screen or from all. */
    function windowsInOrder(): var {
        const everywhere = Config.options.experimental.switcher.windowsFrom === "all";
        const onScreen = Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1;
        const clients = HyprlandData.windowList.filter(client => {
            const origin = Minimize.originOf(client);
            if (everywhere)
                return client.workspace.id > 0 || origin > 0;
            return client.workspace.id === onScreen || origin === onScreen;
        }).sort((a, b) => a.focusHistoryID - b.focusHistoryID);
        const list = [];
        for (const client of clients) {
            const toplevel = ToplevelManager.toplevels.values.find(candidate => TaskbarApps.addressOf(candidate) === client.address);
            if (!toplevel)
                continue;
            list.push({
                toplevel: toplevel,
                address: client.address,
                appId: (toplevel.appId || client.class || "").toLowerCase(),
                title: toplevel.title || client.title || "",
                minimized: Minimize.originOf(client) > 0
            });
        }
        return list;
    }

    function step(delta: int) {
        if (!root.active) {
            root.items = root.windowsInOrder();
            if (root.items.length === 0)
                return;
            root.active = true;
            // The window before this one, or the last when going backwards.
            root.index = root.items.length === 1 ? 0 : (delta > 0 ? 1 : root.items.length - 1);
            const focused = Hyprland.focusedMonitor?.name ?? "";
            root.targetScreen = Quickshell.screens.find(screen => screen.name === focused) ?? Quickshell.screens[0];
            showDelay.restart();
            return;
        }
        if (root.items.length > 0)
            root.index = (root.index + delta + root.items.length) % root.items.length;
    }

    // The pick, brought up once the panel has let go of the keyboard. Brought
    // up while it still held it, the compositor handed focus back to the
    // window from before the moment the panel let go.
    property var pendingPick: null

    function commit() {
        if (!root.active)
            return;
        const picked = root.items[root.index] ?? null;
        const heldKeys = root.holdingKeys;
        root.finish(picked !== null);
        if (!picked)
            return;
        if (heldKeys) {
            root.pendingPick = picked.toplevel;
            pickLater.restart();
        } else {
            TaskbarApps.bringUp(picked.toplevel);
        }
    }

    function cancel() {
        if (root.active)
            root.finish(false);
    }

    function finish(focusing: bool) {
        showDelay.stop();
        root.active = false;
        root.shown = false;
        if (!root.holdingKeys)
            return;
        // Focus is handed to the pick right after, which makes letting go
        // safe. Without one, the same care as the launcher's.
        if (!focusing && FocusReturn.beforeLettingGo())
            letGo.restart();
        else
            root.holdingKeys = false;
    }

    // Drawn only when Alt is held for a moment: a quick Alt+Tab goes back to
    // the window before with nothing flashing on screen.
    Timer {
        id: showDelay
        interval: 120
        onTriggered: {
            if (!root.active)
                return;
            root.shown = true;
            letGo.stop();
            handOver.stop();
            root.holdingKeys = true;
        }
    }
    Timer {
        id: pickLater
        interval: 80
        onTriggered: {
            if (root.pendingPick)
                TaskbarApps.bringUp(root.pendingPick);
            root.pendingPick = null;
        }
    }
    Timer {
        id: letGo
        interval: 80
        onTriggered: {
            root.holdingKeys = false;
            handOver.restart();
        }
    }
    Timer {
        id: handOver
        interval: 60
        onTriggered: FocusReturn.handOver()
    }

    Loader {
        active: root.shown || root.holdingKeys

        sourceComponent: PanelWindow {
            id: panel

            readonly property real cardWidth: 232
            readonly property real thumbHeight: 132
            readonly property int columns: Math.max(1, Math.min(root.items.length, Math.floor(((panel.screen?.width ?? 1920) * 0.8 - 2 * ExLooks.spacing.m) / (panel.cardWidth + ExLooks.spacing.s))))

            screen: root.targetScreen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.holdingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            implicitWidth: plate.width + 64
            implicitHeight: plate.height + 64

            ExSurface {
                id: plate

                anchors.centerIn: parent
                width: grid.implicitWidth + 2 * ExLooks.spacing.m
                height: grid.implicitHeight + 2 * ExLooks.spacing.m
                radius: ExLooks.radius.panel
                elevation: 2
                opacity: root.shown ? 1 : 0
                scale: root.shown ? 1 : 0.96

                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }
                Behavior on scale {
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }

                // The keys while it is up. Tab with Alt is the compositor's,
                // and so is letting go of Alt.
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.cancel();
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                        root.step(1);
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                        root.step(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.commit();
                    else
                        return;
                    event.accepted = true;
                }

                Grid {
                    id: grid

                    x: ExLooks.spacing.m
                    y: ExLooks.spacing.m
                    columns: panel.columns
                    spacing: ExLooks.spacing.s

                    Repeater {
                        model: root.items

                        AbstractButton {
                            id: card

                            ExPrimaryOnly {
                                z: 1
                            }

                            required property var modelData
                            required property int index
                            readonly property bool picked: card.index === root.index

                            implicitWidth: panel.cardWidth
                            implicitHeight: 28 + panel.thumbHeight + 3 * ExLooks.spacing.s
                            hoverEnabled: true
                            onClicked: {
                                root.index = card.index;
                                root.commit();
                            }

                            background: Rectangle {
                                radius: ExLooks.radius.tile
                                color: card.picked ? ExLooks.colors.tonal : "transparent"
                                border.width: card.picked ? 2 : 0
                                border.color: ExLooks.colors.accent

                                // The pick moves with the keys only. A card under
                                // a pointer that was merely resting there when
                                // the panel came up must not take it.
                                ExStateLayer {
                                    ink: card.picked ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                    hovered: card.hovered
                                    pressed: card.down
                                }
                            }

                            contentItem: Item {
                                RowLayout {
                                    id: header

                                    x: ExLooks.spacing.s
                                    y: ExLooks.spacing.s
                                    width: panel.cardWidth - 2 * ExLooks.spacing.s
                                    height: 28
                                    spacing: ExLooks.spacing.s

                                    IconImage {
                                        implicitSize: 18
                                        source: AppSearch.iconFor(card.modelData.appId)
                                    }
                                    ExText {
                                        Layout.fillWidth: true
                                        text: card.modelData.title
                                        textFormat: Text.PlainText
                                        role: "label"
                                        color: card.picked ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                    }
                                }

                                Rectangle {
                                    x: ExLooks.spacing.s
                                    y: header.y + header.height + ExLooks.spacing.s
                                    width: panel.cardWidth - 2 * ExLooks.spacing.s
                                    height: panel.thumbHeight
                                    radius: ExLooks.radius.menuItem
                                    color: ExLooks.colors.surfaceSunken
                                    clip: true

                                    // Live while the panel is up. A minimised window
                                    // is not drawn at all, so it has its icon instead.
                                    ScreencopyView {
                                        anchors.centerIn: parent
                                        visible: !card.modelData.minimized
                                        captureSource: root.shown && !card.modelData.minimized ? card.modelData.toplevel : null
                                        live: true
                                        paintCursor: false
                                        constraintSize: Qt.size(parent.width, parent.height)
                                    }
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: card.modelData.minimized
                                        implicitSize: 48
                                        source: AppSearch.iconFor(card.modelData.appId)
                                        opacity: 0.6
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "altTabNext"
        description: "Switches to the next window while Alt is held"
        onPressed: root.step(1)
    }
    GlobalShortcut {
        name: "altTabPrevious"
        description: "Switches to the previous window while Alt is held"
        onPressed: root.step(-1)
    }
    // Letting go of Alt, and Escape with it, as the compositor hears them
    // during a switch. Dispatched from a function, the shortcut may arrive as
    // a press or a release, and either ends the switch once.
    GlobalShortcut {
        name: "altTabCommit"
        description: "Alt let go of ends a window switch on the window picked"
        onPressed: root.commit()
        onReleased: root.commit()
    }
    GlobalShortcut {
        name: "altTabCancel"
        description: "Escape during a window switch ends it where it began"
        onPressed: root.cancel()
        onReleased: root.cancel()
    }

    IpcHandler {
        target: "switcher"

        function next(): void {
            root.step(1);
        }
        function previous(): void {
            root.step(-1);
        }
        function commit(): void {
            root.commit();
        }
        function cancel(): void {
            root.cancel();
        }
    }
}
