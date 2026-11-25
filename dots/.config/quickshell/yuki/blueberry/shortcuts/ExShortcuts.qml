import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.core.services
import qs.blueberry
import qs.blueberry.looks
import qs.blueberry.motion

// The keys and what the mouse does, over a dimmed screen on the monitor in
// focus, for someone who does not know their way about yet. The same key,
// Escape, or a click outside puts it away.
Scope {
    id: root

    ShortcutsCatalogue {
        id: catalogue
    }

    ExPresence {
        id: presence
        wanted: ExStates.shortcutsOpen
    }

    // The screen in focus as it opens, kept while it is up, as the session menu.
    property var targetScreen: null

    function toggle() {
        if (!ExStates.shortcutsOpen && GlobalStates.screenLocked)
            return;
        ExStates.shortcutsOpen = !ExStates.shortcutsOpen;
    }

    Connections {
        target: ExStates
        function onShortcutsOpenChanged() {
            if (!ExStates.shortcutsOpen)
                return;
            ExStates.launcherOpen = false;
            HyprInput.refresh();
            root.targetScreen = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                ExStates.shortcutsOpen = false;
        }
    }

    Loader {
        active: presence.present && root.targetScreen !== null

        sourceComponent: PanelWindow {
            id: window

            screen: root.targetScreen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:shortcuts"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Component.onCompleted: FocusReturn.remember("exShortcuts")
            Component.onDestruction: FocusReturn.restore("exShortcuts")

            Rectangle {
                anchors.fill: parent
                color: ExLooks.colors.scrim
                opacity: presence.progress
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ExStates.shortcutsOpen = false
            }

            ShortcutsSheet {
                id: sheet

                anchors.centerIn: parent
                groups: catalogue.groups
                roomWidth: window.width - 2 * ExLooks.spacing.xl
                roomHeight: window.height - 2 * ExLooks.spacing.xl
                opacity: presence.progress
                scale: 0.96 + 0.04 * presence.progress
                focus: true
                Component.onCompleted: sheet.forceActiveFocus()
                onCloseAsked: ExStates.shortcutsOpen = false

                // A click on the plate is not one beside it.
                MouseArea {
                    z: -1
                    anchors.fill: parent
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        ExStates.shortcutsOpen = false;
                    else if (event.key === Qt.Key_Down)
                        sheet.scrollBy(48);
                    else if (event.key === Qt.Key_Up)
                        sheet.scrollBy(-48);
                    else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space)
                        sheet.scrollBy(sheet.page());
                    else if (event.key === Qt.Key_PageUp)
                        sheet.scrollBy(-sheet.page());
                    else
                        return;
                    event.accepted = true;
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            if (!ExStates.shortcutsOpen)
                root.toggle();
        }
        function close(): void {
            ExStates.shortcutsOpen = false;
        }
        function isOpen(): bool {
            return ExStates.shortcutsOpen;
        }
        /** What it tells, a line each: the group, what is done, the keys. */
        function list(): string {
            return catalogue.groups.map(group => group.rows.map(row => `${group.title}\t${row.text}\t${row.caps.map(cap => cap.text ?? (cap.mouse ? `${cap.mouse} button` : cap.glyphs.join("+"))).join(" ")}`).join("\n")).join("\n");
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Opens or closes the list of keys"
        onPressed: root.toggle()
    }
}
