pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.startMenu
import qs.modules.waffle.startMenu.searchPage

WBarAttachedPanelContent {
    id: root

    readonly property bool searching: LauncherSearch.query.length > 0

    onSearchingChanged: {
        if (root.searching)
            resultsLoader.active = true;
    }

    StartMenuContext {
        id: context
        onLaunched: query => {
            root.rememberQuery(query);
            GlobalStates.searchPanelOpen = false;
        }
    }

    // Newest first, no repeats, and only so many kept.
    property int recentQueryLimit: 8
    function rememberQuery(query) {
        const trimmed = (query ?? "").trim();
        if (trimmed.length === 0)
            return;
        const kept = Persistent.states.search.recentQueries.filter(entry => entry !== trimmed);
        Persistent.states.search.recentQueries = [trimmed].concat(kept).slice(0, root.recentQueryLimit);
    }

    Keys.onPressed: event => {
        // The field holds focus, so only what a single-line field leaves alone
        // has to be handled here.
        if (event.key === Qt.Key_Down) {
            const maxIndex = Math.max(0, LauncherSearch.results.length - 1);
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
                implicitWidth: Looks.sizes.menuWidth // the start menu stands in the same place
                horizontalPadding: 32
                focus: true
                text: LauncherSearch.query
                onTextChanged: {
                    LauncherSearch.query = text;
                }
                onAccepted: {
                    context.accepted();
                }
            }

            Item {
                implicitHeight: 640
                Layout.fillWidth: true

                Loader {
                    anchors.fill: parent
                    visible: !root.searching
                    sourceComponent: quickAccessComp
                }
                Loader {
                    id: resultsLoader
                    anchors.fill: parent
                    visible: root.searching
                    active: false
                    sourceComponent: resultsComp
                }
            }
        }
    }

    Component {
        id: resultsComp
        SearchPageContent {
            context: context
        }
    }

    Component {
        id: quickAccessComp
        RecentSearches {
            onQueryChosen: query => {
                LauncherSearch.query = query;
                searchBar.searchInput.cursorPosition = query.length;
                searchBar.forceFocus();
            }
        }
    }
}
