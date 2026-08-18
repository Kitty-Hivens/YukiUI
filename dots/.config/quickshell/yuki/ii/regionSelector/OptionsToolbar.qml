pragma ComponentBehavior: Bound
import qs
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.core.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    // Assigned in both directions rather than bound one way and written back the
    // other. Binding currentIndex to selectionMode while the tab bar's own change
    // handler assigned selectionMode closed a cycle, which the engine reports as a
    // binding loop. An assignment that lands on the value already there emits
    // nothing, so the two settle after a single hop.
    function syncTabFromSelectionMode() {
        if (root.selectionMode === undefined)
            return;
        tabBar.currentIndex = (root.selectionMode === RegionSelection.SelectionMode.RectCorners) ? 0 : 1;
    }
    onSelectionModeChanged: root.syncTabFromSelectionMode()
    Component.onCompleted: root.syncTabFromSelectionMode()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // Until the synchronizer has delivered a mode there is nothing to report
        // back, and reporting anyway would have announced whichever tab happened
        // to be current as the user's choice.
        onCurrentIndexChanged: {
            if (root.selectionMode === undefined)
                return;
            root.selectionMode = (tabBar.currentIndex === 0)
                ? RegionSelection.SelectionMode.RectCorners
                : RegionSelection.SelectionMode.Circle;
        }
    }
}
