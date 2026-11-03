pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.core.services
import qs.blueberry.settings

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

    readonly property string entry: "blueberrySettings.qml"
    /** The settings window's title, which that file keeps untranslated. */
    readonly property string title: "Blueberry Settings"

    function open(surface, page) {
        if (surface !== "settings" && surface !== "appearance")
            return;
        const start = page.length > 0 ? page : (surface === "appearance" ? "personalization" : "");
        const path = Quickshell.shellPath(root.entry);
        // A window already open is brought up on the page asked for. Another
        // process would hold a second copy of the display state and write the
        // config alongside the first. It is raised from here, as the dock
        // raises a window: focus alone leaves a window behind the ones over
        // it, and one that is minimised has to be put back first.
        const shown = ToplevelManager.toplevels.values.find(toplevel => toplevel.title === root.title);
        if (shown)
            TaskbarApps.bringUp(shown);
        // Otherwise one is started, the page travelling in the environment,
        // which is where the window reads it. One still on its way up has no
        // window yet and is only told the page.
        Quickshell.execDetached(["sh", "-c",
            "qs -p \"$1\" ipc call settingsWindow present \"$2\" >/dev/null 2>&1 || YUKIUI_SETTINGS_PAGE=\"$2\" exec qs -n -p \"$1\"",
            "yuki-settings", path, start]);
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
