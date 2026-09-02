pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core.services
import qs.ii.systemSettings

/**
 * This desktop's answer about the windows it owns but does not draw.
 *
 * Lives in the environment's own tree, so it exists exactly while this desktop
 * is the one running. That is what makes core able to ask for "the settings"
 * without naming anybody: when another desktop is up, this object is gone and
 * the request reaches whatever that desktop registered instead, or nothing.
 *
 * The windows are started detached rather than held as a Process. A Process
 * kills its child when it is destroyed, and every reload destroys the whole
 * tree without the desktop having changed, so holding them would take the open
 * settings window down on every reload of the shell. Leaving on a change of
 * desktop is the window's own business, decided the way a panel decides whether
 * to be mapped at all.
 */
QtObject {
    id: root

    /** Surface name to the entry that draws it, as a path from the shell root. */
    readonly property var entries: ({
        settings: "systemSettings.qml",
        appearance: "appearanceSettings.qml"
    })

    function open(surface, page) {
        const entry = root.entries[surface];
        if (entry === undefined)
            return;
        const path = Quickshell.shellPath(entry);
        // The page travels in the environment, which is where the window reads
        // it. Handed over as arguments rather than through a shell, so a path
        // with a space in it is not something anyone has to think about.
        if (page.length > 0)
            Quickshell.execDetached(["env", `YUKIUI_SETTINGS_PAGE=${page}`, "qs", "-p", path]);
        else
            Quickshell.execDetached(["qs", "-p", path]);
    }

    readonly property Connections requests: Connections {
        target: Surfaces
        function onRequested(surface, page) {
            root.open(surface, page);
        }
    }

    /**
     * What this desktop's settings offer, handed to core as plain data.
     *
     * Republished whenever the catalogue changes, which it does when a plugin
     * contributes a page or the language changes.
     */
    readonly property var catalogue: SystemPages.pages.map(page => ({
        key: page.key,
        name: page.name,
        icon: page.icon,
        description: page.description,
        keywords: page.keywords
    }))

    onCatalogueChanged: Surfaces.publish(root.catalogue)
    Component.onCompleted: Surfaces.publish(root.catalogue)
    Component.onDestruction: Surfaces.withdraw()
}
