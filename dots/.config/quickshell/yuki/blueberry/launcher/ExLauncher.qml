import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// The launcher: a panel of its own over the dock, on the screen in focus. A
// window rather than a popup of the dock, because it has to take the keyboard
// to be typed into, and a popup that takes no grab never gets it.
//
// With keepReady it is built a moment after the shell comes up and is never
// taken down again: closed, its window is parked, a point in a corner that
// takes no pointer and holds no keyboard, with nothing drawn on it. Built on
// each opening it took a tenth of a second when warm and several seconds when
// it was the first thing opened after a game, the window itself included,
// which the compositor makes anew each time one is shown.
Scope {
    id: root

    property var targetScreen: null

    /** Holds the keyboard. Let go a moment after closing when the focus has to be made safe first. */
    property bool holdingKeys: false

    readonly property bool keepReady: Config.ready && Config.options.blueberry.keepReady

    function focusedScreen(): var {
        const focused = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(screen => screen.name === focused) ?? Quickshell.screens[0];
    }

    Connections {
        target: ExStates

        function onLauncherOpenChanged() {
            if (!ExStates.launcherOpen) {
                if (FocusReturn.beforeLettingGo())
                    letGo.restart();
                else
                    root.holdingKeys = false;
                return;
            }
            letGo.stop();
            handOver.stop();
            root.holdingKeys = true;
            root.targetScreen = root.focusedScreen();
            loader.active = true;
        }
    }

    // Built ahead once the shell has settled, so the first opening is as quick
    // as the others. Not at once: the shell has enough to build as it starts.
    Timer {
        id: buildAhead
        interval: 3000
        running: root.keepReady && !loader.active
        onTriggered: {
            if (!root.targetScreen)
                root.targetScreen = root.focusedScreen();
            loader.active = true;
        }
    }

    // Switched off while it sits parked, it goes now rather than on the next close.
    onKeepReadyChanged: {
        if (!root.keepReady && !ExStates.launcherOpen && (loader.item?.parked ?? false))
            loader.active = false;
    }

    LaunchWatch {}

    // Time for the compositor to have let go of the focus before the launcher
    // lets go of the keyboard, and for that to land before focus is handed on.
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
        id: loader
        active: false
        // Built ahead, it is built a little at a time, so the shell does not
        // stop for it. Opened before that is done, it shows once it is.
        asynchronous: true
        // Closed again before it was built, a quick second press of Super, it
        // never shows its way out, which is what unloads it, so it goes here.
        onLoaded: {
            if (!ExStates.launcherOpen && !root.keepReady)
                loader.active = false;
        }

        sourceComponent: PanelWindow {
            id: panel

            readonly property string edge: Config.options.blueberry.dock.edge
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property bool centered: Config.options.blueberry.dock.alignment !== "start"
            readonly property real shadowRoom: 32
            // What the dock takes up at its edge, which the panel stands clear of.
            readonly property real dockRoom: ExLooks.dock.thickness + (Config.options.blueberry.dock.style !== "attached" ? ExLooks.dock.floatingGap : 0)
            /**
             * Closed and done showing the way out. The window is then a point,
             * since a parked window the size of the screen is a layer the
             * compositor blends, and blurs, over everything whenever anything
             * under it changes.
             */
            readonly property bool parked: !ExStates.launcherOpen && surface.progress === 0

            screen: root.targetScreen
            color: "transparent"
            // Over the dock as well: a click on it, the launcher's own button
            // included, closes the launcher like any other click beside it.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:launcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.holdingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // The whole screen. Holding the keyboard exclusively, the launcher
            // gets no word from the compositor of a click beside it, which is
            // dropped instead, the dock's included, so it takes those clicks
            // itself and closes. On the way out only the panel takes the pointer.
            anchors {
                top: true
                left: true
                bottom: !panel.parked
                right: !panel.parked
            }
            implicitWidth: 1
            implicitHeight: 1
            mask: ExStates.launcherOpen ? wholeWindow : panel.parked ? nothing : panelOnly

            Region {
                id: wholeWindow
                item: beside
            }
            Region {
                id: panelOnly
                item: surface
            }
            Region {
                id: nothing
                item: nothingItem
            }
            Item {
                id: nothingItem
            }

            MouseArea {
                id: beside
                anchors.fill: parent
                onPressed: ExStates.launcherOpen = false
            }

            // Taken once the panel holds the keyboard, not before. A layer
            // turning exclusive again ends whatever grab is up, its own
            // included, so reopened on its way out the launcher had its new
            // grab cleared at once and closed itself.
            HyprlandFocusGrab {
                windows: [panel]
                active: ExStates.launcherOpen && beside.Window.active
                onCleared: ExStates.launcherOpen = false
            }

            // The panel slides out from behind the dock, so everything on the
            // dock's side of the dock's inner edge is cut off. It never passes
            // over the dock, and the dock stands in front of it on the way.
            Item {
                id: track

                readonly property real cut: panel.dockRoom
                x: panel.edge === "left" ? track.cut : 0
                y: panel.edge === "top" ? track.cut : 0
                width: panel.width - (panel.vertical ? track.cut : 0)
                height: panel.height - (panel.vertical ? 0 : track.cut)
                clip: true

                ExFlyoutSurface {
                    id: surface

                    open: ExStates.launcherOpen
                    edge: panel.edge
                    // Out from behind the dock, the whole of it at once, and
                    // back in the same way. Far enough to start out of sight.
                    entry: panel.edge
                    entryTravel: (panel.vertical ? width : height) + panel.shadowRoom
                    // Against the dock, along it where the dock gathers its icons.
                    restX: (panel.vertical ? (panel.edge === "left" ? panel.dockRoom + panel.shadowRoom : panel.width - width - panel.dockRoom - panel.shadowRoom)
                        : (panel.centered ? (panel.width - width) / 2 : panel.shadowRoom)) - track.x
                    restY: (panel.vertical ? (panel.height - height) / 2
                        : (panel.edge === "top" ? panel.dockRoom + panel.shadowRoom : panel.height - height - panel.dockRoom - panel.shadowRoom)) - track.y
                    width: content.implicitWidth
                    height: content.implicitHeight
                    elevation: 2
                    // Unloaded once the way out has been shown, not before, and
                    // only when it is not kept.
                    onProgressChanged: {
                        if (progress === 0 && !ExStates.launcherOpen && !root.keepReady)
                            loader.active = false;
                    }

                    LauncherContent {
                        id: content
                        anchors.fill: parent
                        Component.onCompleted: content.reset()

                        // Opened again while still on its way out, it is the same
                        // panel and still holds the last search.
                        Connections {
                            target: ExStates
                            function onLauncherOpenChanged() {
                                if (ExStates.launcherOpen)
                                    content.reset();
                                else
                                    content.dismissMenu();
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "search"

        function toggle(): void {
            ExStates.launcherOpen = !ExStates.launcherOpen;
        }
        function open(): void {
            ExStates.launcherOpen = true;
        }
        function close(): void {
            ExStates.launcherOpen = false;
        }
        function toggleReleaseInterrupt(): void {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles the launcher on press"
        onPressed: ExStates.launcherOpen = !ExStates.launcherOpen
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles the launcher when Super is released alone"
        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            ExStates.launcherOpen = !ExStates.launcherOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Keeps a Super release that came with another key from toggling the launcher"
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }
}
