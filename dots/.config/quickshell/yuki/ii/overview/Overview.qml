import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common
import qs.ii
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: IiStates.overviewOpen

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: IiStates.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: IiStates.overviewOpen ? backdropArea : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!IiStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    // Asked for here rather than after the grab is dropped, so
                    // the wait stays the one the service keeps and does not
                    // become two of them back to back.
                    if (IiStates.overviewFocusHandled)
                        FocusReturn.discard("overview");
                    else
                        FocusReturn.restore("overview");
                } else {
                    IiStates.overviewFocusHandled = false;
                    FocusReturn.remember("overview");
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                }
                delayedGrabTimer.restart();
            }
        }

        // Scope the grab to this window (plus the OSK when open), never the bar. A shared grab
        // that included the bar left fullscreen games unfocused on dismiss, and with
        // no_focus_fallback their pointer lock never re-armed.
        HyprlandFocusGrab {
            id: grab
            windows: (GlobalStates.oskOpen && GlobalStates.oskWindow) ? [panelWindow, GlobalStates.oskWindow] : [panelWindow]
            active: false
            onCleared: () => {
                if (!active) IiStates.overviewOpen = false;
            }
        }

        Timer {
            id: delayedGrabTimer
            interval: Appearance.animation.elementMoveFast.duration
            onTriggered: grab.active = IiStates.overviewOpen
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        MouseArea {
            id: backdropArea
            anchors.fill: parent
            // Click on empty space (not the search bar or a workspace/window) dismisses the overview.
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: IiStates.overviewOpen = false
        }

        Column {
            id: columnLayout
            visible: IiStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    IiStates.overviewOpen = false;
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: IiStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: (panelWindow.searchingText == "")
                }
            }
        }
    }

    function toggleClipboard() {
        if (IiStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            IiStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        IiStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (IiStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            IiStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        IiStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            IiStates.overviewOpen = !IiStates.overviewOpen;
        }
        function workspacesToggle() {
            IiStates.overviewOpen = !IiStates.overviewOpen;
        }
        function close() {
            IiStates.overviewOpen = false;
        }
        function open() {
            IiStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            IiStates.overviewOpen = !IiStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            IiStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            IiStates.overviewOpen = !IiStates.overviewOpen;
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
            IiStates.overviewOpen = !IiStates.overviewOpen;
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
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
