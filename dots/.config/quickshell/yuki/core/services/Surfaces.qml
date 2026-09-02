pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The windows a desktop owns but does not draw, and what they offer.
 *
 * Settings are per desktop: each builds them on its own structure, so there is no
 * shared settings window and core must not name anybody's. What core needs is to
 * open "the settings, on this page" and to search what pages exist, and both
 * answers belong to whichever desktop is up.
 *
 * So nothing is started here. A request is raised and the environment that has
 * such a surface answers, the same shape as
 * [GlobalStates.panelDismissRequested]. An environment without one answers
 * nothing, and asking is then a no operation rather than a window belonging to a
 * desktop that is not running.
 */
Singleton {
    id: root

    /**
     * Named, never pathed: a caller must not have to know whose window it is, and
     * the answer must be free to differ per desktop.
     *
     * `page` is a hint the surface may ignore. Only a settings window reads one.
     */
    signal requested(string surface, string page)

    function open(surface, page) {
        root.requested(surface, page ?? "");
    }

    /**
     * The pages the active desktop's settings offer, as plain data.
     *
     * Published by the environment rather than imported from it, which is the
     * whole point: the launcher searches this without naming a desktop, and a
     * desktop with no settings of its own leaves it empty rather than lending
     * somebody else's.
     *
     * Entries carry `key`, `name`, `icon`, `description` and `keywords`. No live
     * state and no component path: a searcher needs neither, and a status line
     * read from here would tie every service behind it to this process.
     */
    property var pages: []

    function publish(entries) {
        root.pages = entries ?? [];
    }

    function withdraw() {
        root.pages = [];
    }

    /**
     * The way in from another process.
     *
     * A window opened from inside the settings window is the case: that is a
     * process of its own with no environment in it, so a signal raised there
     * would be heard by nobody. It asks the shell, and the shell asks the
     * environment.
     */
    IpcHandler {
        target: "surfaces"

        function open(surface: string, page: string): void {
            root.open(surface, page);
        }
    }
}
