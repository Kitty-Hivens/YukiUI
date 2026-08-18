pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks

GridLayout {
    id: root

    property list<var> desktopEntries: []

    // Which panel to put away afterwards is the caller's to decide -- the grid is
    // in the start menu and in the search panel both.
    signal entryLaunched

    columnSpacing: 0
    rowSpacing: 0

    uniformCellHeights: true
    uniformCellWidths: true

    Repeater {
        model: root.desktopEntries
        delegate: StartAppButton {
            id: pinnedAppButton
            required property var modelData
            desktopEntry: modelData
            onClicked: {
                root.entryLaunched();
                desktopEntry.execute();
            }
        }
    }
}
