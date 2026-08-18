import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.waffle
import qs.waffle.bar

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onSearchOpenChanged() {
            if (GlobalStates.searchOpen)
                WPanels.keepOnly("searchOpen");
            if (GlobalStates.searchOpen) {
                LauncherSearch.query = "";
                panelLoader.active = true;
            }
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.searchOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wStartMenu"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                left: Config.options.waffles.bar.leftAlignApps
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            // Input only where the panel is drawn, so a click past it reaches what is
            // behind and the focus grab can close the panel.
            mask: Region {
                item: content.visibleArea
            }

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow].concat(WBarWindows.windows)
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onSearchOpenChanged() {
                    if (!GlobalStates.searchOpen)
                        content.close();
                }
            }

            StartMenuContent {
                id: content
                anchors.fill: parent
                focus: true

                onClosed: {
                    GlobalStates.searchOpen = false;
                    panelLoader.active = false;
                    LauncherSearch.query = "";
                }
            }
        }
    }

    function toggleClipboard() {
        if (LauncherSearch.query.startsWith(Config.options.search.prefix.clipboard) || !GlobalStates.searchOpen) {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        LauncherSearch.ensurePrefix(Config.options.search.prefix.clipboard);
    }
    function toggleEmojis() {
        if (LauncherSearch.query.startsWith(Config.options.search.prefix.emojis) || !GlobalStates.searchOpen) {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        LauncherSearch.ensurePrefix(Config.options.search.prefix.emojis);
    }

    IpcHandler {
        target: "search"

        function toggle(): void {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        function close(): void {
            GlobalStates.searchOpen = false;
        }
        function open(): void {
            GlobalStates.searchOpen = true;
        }
        function toggleReleaseInterrupt(): void {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle(): void {
            root.toggleClipboard();
        }
        function emojiToggle(): void {
            root.toggleEmojis();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            root.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            root.toggleEmojis();
        }
    }
}
