import qs
import qs.core.services
import QtQuick
import Quickshell
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Which of this environment's panels are open.
 *
 * Named for what this desktop actually shows: what is called an overview in the
 * other environment is the task view here, and what opens on the left there is
 * the action centre here. Sharing one set of names made the two read as the same
 * surface when they never were. See [IiStates] for the other half.
 */
Singleton {
    id: root

    property bool barOpen: true
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool sessionOpen: false
    property bool searchOpen: false
    property bool searchPanelOpen: false
    property bool widgetsOpen: false

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
}
