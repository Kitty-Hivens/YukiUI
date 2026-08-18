import qs
import qs.core.services
import QtQuick
import Quickshell
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Which of this environment's panels are open.
 *
 * Panels used to steer each other through one set of flags in the shell root,
 * named after the panels of this environment. The other environment then wrote
 * to those same names meaning its own surfaces, so a name said one thing on one
 * desktop and another thing on the other. A panel belongs to the environment
 * that draws it, and so does the flag that opens it.
 */
Singleton {
    id: root

    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool overviewFocusHandled: false
    property bool regionSelectorOpen: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    // Opening the panel that shows notifications is what marks them seen; it was
    // done in the shell root back when one flag served both environments.
    onSidebarRightOpenChanged: {
        Notifications.viewerOpen = root.sidebarRightOpen;
        if (root.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    // Something drawn inside a panel asked to be dismissed without naming one.
    Connections {
        target: GlobalStates
        function onPanelDismissRequested() {
            root.sidebarRightOpen = false;
        }
    }

    /** The environment these flags speak for. */
    readonly property string environmentId: "ii"

    /**
     * A panel of an environment that is not up is not open, whatever the flag
     * last said.
     *
     * These singletons outlive the environment they describe: the registry
     * destroys the object it built, not the module that was imported to build
     * it. So a panel left open across a swap went on speaking for a desktop that
     * no longer exists -- and because opening the notification list is what
     * suppresses popups, the environment that replaced it came up with its
     * notifications silently held back.
     */
    function closeAll() {
        root.sidebarLeftOpen = false;
        root.sidebarRightOpen = false;
        root.mediaControlsOpen = false;
        root.osdBrightnessOpen = false;
        root.osdVolumeOpen = false;
        root.overlayOpen = false;
        root.overviewOpen = false;
        root.overviewFocusHandled = false;
        root.regionSelectorOpen = false;
        root.screenTranslatorOpen = false;
        root.sessionOpen = false;
        root.wallpaperSelectorOpen = false;
    }

    Connections {
        target: Environments
        function onActiveIdChanged() {
            if (Environments.activeId !== root.environmentId)
                root.closeAll();
        }
    }
}
