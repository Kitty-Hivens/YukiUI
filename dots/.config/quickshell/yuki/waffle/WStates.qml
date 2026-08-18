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

    /** The environment these flags speak for. */
    readonly property string environmentId: "waffle"

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
        root.osdBrightnessOpen = false;
        root.osdVolumeOpen = false;
        root.overviewOpen = false;
        root.regionSelectorOpen = false;
        root.sessionOpen = false;
        root.searchOpen = false;
        root.searchPanelOpen = false;
        root.widgetsOpen = false;
    }

    Connections {
        target: Environments
        function onActiveIdChanged() {
            if (Environments.activeId !== root.environmentId)
                root.closeAll();
        }
    }
}
