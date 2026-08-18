pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.services

/**
 * The panels that hang off the bar, and the two rules they all follow: only one of
 * them is out at a time -- pressing a bar button puts away whatever the last one
 * opened -- and none of them is out over a fullscreen game.
 *
 * The second rule is the one the other family already keeps on its sidebars. A
 * panel mapped over a fullscreen window sits under it on the Top layer anyway, and
 * the focus grab it takes freezes the game's pointer lock, so the game is left
 * unplayable by a panel nobody can see. It is gated on something actually being
 * fullscreen rather than on game mode being engaged, so switching game mode on by
 * hand still leaves every panel reachable.
 */
Singleton {
    id: root

    readonly property list<string> exclusive: ["searchOpen", "searchPanelOpen", "sidebarLeftOpen", "sidebarRightOpen", "widgetsOpen"]
    /// Everything the bar can put on screen, including the ones that are not part of
    /// the one-at-a-time rule: over a fullscreen game none of them belongs.
    readonly property list<string> mappable: ["searchOpen", "searchPanelOpen", "sidebarLeftOpen", "sidebarRightOpen", "widgetsOpen", "overviewOpen", "sessionOpen"]

    readonly property bool blocked: GameMode.anyFullscreen

    function keepOnly(state) {
        for (const other of root.exclusive) {
            if (other !== state && GlobalStates[other])
                GlobalStates[other] = false;
        }
        root.enforce();
    }

    /// Puts away anything that is out, and refuses anything opened while it is: a
    /// shortcut pressed mid-game must not map a panel over it either.
    function enforce() {
        if (!root.blocked)
            return;
        for (const state of root.mappable) {
            if (GlobalStates[state])
                GlobalStates[state] = false;
        }
    }

    onBlockedChanged: root.enforce()

    Connections {
        target: GlobalStates
        function onSearchOpenChanged() {
            root.enforce();
        }
        function onSearchPanelOpenChanged() {
            root.enforce();
        }
        function onSidebarLeftOpenChanged() {
            root.enforce();
        }
        function onSidebarRightOpenChanged() {
            root.enforce();
        }
        function onWidgetsOpenChanged() {
            root.enforce();
        }
        function onOverviewOpenChanged() {
            root.enforce();
        }
        function onSessionOpenChanged() {
            root.enforce();
        }
    }
}
