import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.bar
import qs.modules.waffle.bar.tray

Scope {
    id: root
    
    LazyLoader {
        id: barLoader
        active: GlobalStates.barOpen
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

                // Unmapping under a fullscreen window is what lets Hyprland direct-scanout
                // it, and the ii bar does that with a `visible` binding. The same binding
                // here segfaulted Quickshell every time a window went fullscreen.
                //
                // What the dump shows, and no more than that: tearing the window down runs
                // setParentItem, whose cascade of derefWindow calls reaches
                // QQuickMouseArea::itemChange, which re-evaluates a binding that then asks
                // a half-destroyed window for QQuickItem::window(). Which binding is not
                // known. Nor is why the ii bar survives it -- it has tooltips, popups and
                // tray menus of its own, so "this bar has more attached to it" was a guess
                // and is not an explanation.
                //
                // Left mapped until the cause is found on something other than the user's
                // running shell. Putting the binding back before then costs them the
                // shell, which is what it did.

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
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
