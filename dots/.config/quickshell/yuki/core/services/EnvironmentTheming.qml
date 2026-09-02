pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.core
import Quickshell

/**
 * Keeps the desktop outside the shell in step with the environment that is up.
 *
 * Panels are rebuilt in process when the environment changes; everything else --
 * the toolkit theme, the icon set, the Qt colour scheme, the compositor's own
 * colours -- lives in files that something has to rewrite. Nothing did, so a
 * switch repainted the panels and left the rest belonging to whoever was up last.
 *
 * The decision of whether there is anything to do is left to switchwall, which
 * keeps a stamp of the environment it last themed for. That way this fires on
 * the first environment of the session as well, and costs nothing when the
 * answer is "the same one", which is the usual case.
 */
Singleton {
    id: root

    /// Woken from shell.qml, since a singleton nobody has asked for is not watching.
    function load() {}

    Connections {
        target: Environments
        function onActiveIdChanged() {
            if (Environments.activeId.length === 0)
                return;
            settle.restart();
        }
    }

    /// The swap is paced in two beats and the cycle key can be held down, so the
    /// environment settles more than once per decision. Rewriting the desktop's
    /// theme costs a matugen run; it waits for the last one.
    Timer {
        id: settle
        interval: 400
        repeat: false
        onTriggered: {
            const id = Environments.activeId;
            if (id.length === 0)
                return;
            Quickshell.execDetached([
                Directories.wallpaperSwitchScriptPath,
                "--noswitch",
                "--if-family-changed"
            ]);
        }
    }
}
