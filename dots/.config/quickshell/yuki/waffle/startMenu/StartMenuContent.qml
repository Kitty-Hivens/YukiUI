pragma ComponentBehavior: Bound
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import qs.waffle.startMenu.startPage
import qs.waffle.startMenu.searchPage

WBarAttachedPanelContent {
    id: root

    property bool searching: false
    property string searchText: LauncherSearch.query

    onSearchingChanged: {
        if (root.searching)
            searchPageLoader.active = true;
    }

    StartMenuContext {
        id: context
        onLaunched: {
            GlobalStates.searchOpen = false;
        }
    }

    Keys.onPressed: event => {
        // This handler replaces the base one rather than adding to it, so what the
        // base did for Escape has to be done here or the menu cannot be dismissed
        // with the key that dismisses every other panel.
        if (event.key === Qt.Key_Escape) {
            root.close();
            event.accepted = true;
            return;
        }

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            searchBar.forceFocus();
            if (event.modifiers & Qt.ControlModifier) {
                // Delete word before cursor
                let text = searchBar.text;
                let pos = searchBar.searchInput.cursorPosition;
                if (pos > 0) {
                    // Find the start of the previous word
                    let left = text.slice(0, pos);
                    let match = left.match(/(\s*\S+)\s*$/);
                    let deleteLen = match ? match[0].length : 1;
                    searchBar.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                    searchBar.searchInput.cursorPosition = pos - deleteLen;
                }
            } else {
                // Delete character before cursor if any
                if (searchBar.searchInput.cursorPosition > 0) {
                    searchBar.text = searchBar.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.text.slice(searchBar.searchInput.cursorPosition);
                    searchBar.searchInput.cursorPosition -= 1;
                }
            }
            // Always move cursor to end after programmatic edit
            searchBar.searchInput.cursorPosition = searchBar.text.length;
            event.accepted = true;
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                searchBar.forceFocus();
                // Insert the character at the cursor position
                searchBar.text = searchBar.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                context.setCurrentIndex(0);
            }
        }

        // Arrow keys for item navigation
        if (event.key === Qt.Key_Down) {
            let maxIndex = Math.max(0, LauncherSearch.results.length - 1);
            context.setCurrentIndex(Math.min(context.currentIndex + 1, maxIndex));
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            context.setCurrentIndex(Math.max(context.currentIndex - 1, 0));
            event.accepted = true;
        }
    }

    contentItem: WPane {
        contentItem: WPanelPageColumn {
            SearchBar {
                id: searchBar
                Layout.fillWidth: true
                implicitWidth: Looks.sizes.startMenuWidth
                horizontalPadding: 32
                // verticalPadding: root.searching ? 32 : 16 // TODO: make this not nuke the panel
                Synchronizer on searching {
                    property alias target: root.searching
                }
                focus: true
                text: root.searchText
                onTextChanged: {
                    LauncherSearch.query = text;
                }
                onAccepted: {
                    context.accepted();
                }
            }
            Item {
                implicitHeight: Looks.sizes.menuHeight - searchBar.implicitHeight
                Layout.fillWidth: true
                // Both pages stay for as long as the menu is open. Swapping one Loader
                // between them tore down the start page on the first character typed and
                // built it again on the last one deleted, and building it means walking
                // every installed application once per category.
                Loader {
                    anchors.fill: parent
                    visible: !root.searching
                    sourceComponent: startPageComp
                }
                Loader {
                    id: searchPageLoader
                    anchors.fill: parent
                    visible: root.searching
                    active: false
                    sourceComponent: searchPageComp
                }
            }
        }
    }

    Component {
        id: searchPageComp
        SearchPageContent {
            context: context
        }
    }

    Component {
        id: startPageComp
        StartPageContent {}
    }
}
