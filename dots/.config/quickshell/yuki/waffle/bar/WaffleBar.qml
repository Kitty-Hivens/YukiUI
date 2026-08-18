import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.waffle.bar
import qs.waffle.bar.tray
import qs.waffle

Scope {
    id: root
    
    LazyLoader {
        id: barLoader
        active: WStates.barOpen
        component: Variants {
            model: Quickshell.screens
            delegate: PanelWindow { // Bar window
                id: barRoot
                required property var modelData
                screen: modelData
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: implicitHeight
                WlrLayershell.namespace: "quickshell:bar"

                anchors {
                    left: true
                    right: true
                    bottom: Config.options.waffles.bar.bottom
                    top: !Config.options.waffles.bar.bottom
                }

                color: "transparent"
                implicitHeight: content.implicitHeight
                implicitWidth: content.implicitWidth

                // Unmapped under a fullscreen window so Hyprland can direct-scanout it,
                // which is what VRR pacing wants.
                //
                // This binding used to segfault the shell on every fullscreen. Tearing
                // the window down runs setParentItem, whose cascade of derefWindow calls
                // reaches QQuickMouseArea::itemChange, which re-evaluates a binding that
                // then asks a half-destroyed window for QQuickItem::window(). The binding
                // was the task row's preview popup: it hangs off a MouseArea and had its
                // anchor window bound to that MouseArea's QsWindow. The ii bar survives
                // the same unmapping because every QsWindow.window it reads sits inside a
                // Loader that is inactive unless a menu or a tooltip is actually open --
                // not because it has less attached to it. The preview takes its window
                // once now instead of binding it.
                //
                // Deferring the unmap out of the binding update does not help: the
                // teardown is unsafe whenever a live binding is left for it to walk back
                // into, whatever point in the event loop it runs at.
                property bool fullscreenHere: Hyprland.workspaces.values.some(ws => ws.active
                    && ws.monitor?.name == barRoot.modelData.name
                    && ws.toplevels.values.some(w => w.wayland?.fullscreen))
                visible: !(Config.options.waffles.bar.hideWhenFullscreen && barRoot.fullscreenHere)

                Component.onCompleted: WBarWindows.add(barRoot)
                Component.onDestruction: WBarWindows.remove(barRoot)

                WaffleBarContent {
                    id: content
                    anchors.fill: parent
                }
            }
        }
    }

    // Where a tray icon is drawn while it is being carried. One per screen, beside
    // the bar rather than inside it, because the bar clips.
    Variants {
        model: Quickshell.screens
        delegate: TrayDragLayer {
            required property var modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            WStates.barOpen = !WStates.barOpen
        }

        function close(): void {
            WStates.barOpen = false
        }

        function open(): void {
            WStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            WStates.barOpen = !WStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            WStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            WStates.barOpen = false;
        }
    }
}
