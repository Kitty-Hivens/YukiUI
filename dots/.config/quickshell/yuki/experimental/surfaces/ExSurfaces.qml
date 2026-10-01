pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.core.services
import qs.experimental.settings

/**
 * This environment's answer when the shell asks for the settings.
 *
 * Both names the shell asks by, the settings and the appearance settings,
 * open the one settings window here: appearance on its personalization page.
 * The window is started detached, as a process of its own, since a reload of
 * the shell would take down anything it held.
 */
QtObject {
    id: root

    readonly property string entry: "experimentalSettings.qml"

    function open(surface, page) {
        if (surface !== "settings" && surface !== "appearance")
            return;
        const start = page.length > 0 ? page : (surface === "appearance" ? "personalization" : "");
        const path = Quickshell.shellPath(root.entry);
        // The page travels in the environment, which is where the window reads it.
        if (start.length > 0)
            Quickshell.execDetached(["env", `YUKIUI_SETTINGS_PAGE=${start}`, "qs", "-p", path]);
        else
            Quickshell.execDetached(["qs", "-p", path]);
    }

    readonly property Connections requests: Connections {
        target: Surfaces
        function onRequested(surface, page) {
            root.open(surface, page);
        }
    }

    readonly property SettingsCatalogue settingsCatalogue: SettingsCatalogue {}

    /** What the settings offer, for the launcher's search. */
    readonly property var catalogue: root.settingsCatalogue.pages.map(page => ({
        key: page.key,
        name: page.name,
        icon: page.glyph,
        description: page.description,
        keywords: page.keywords
    }))

    onCatalogueChanged: Surfaces.publish(root.catalogue)
    Component.onCompleted: Surfaces.publish(root.catalogue)
    Component.onDestruction: Surfaces.withdraw()
}
