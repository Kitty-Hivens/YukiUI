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
}
