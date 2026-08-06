pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.startMenu.startPage

// What the panel shows before anything is typed. The applications pinned to Start
// stand in for the "top apps" of the real thing, which are worked out from how
// often each is started -- nothing here counts that.
BodyRectangle {
    id: root

    signal entryLaunched

    readonly property list<DesktopEntry> pinnedEntries: Config.options.launcher.pinnedApps.map(appId => AppSearch.entryFor(appId)).filter(entry => entry !== null)

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 32
            rightMargin: 32
            topMargin: 25
            bottomMargin: 30
        }
        spacing: 16

        WText {
            Layout.fillWidth: true
            text: Translation.tr("Quick access")
            font.pixelSize: Looks.font.pixelSize.large
            font.weight: Looks.font.weight.stronger
        }

        BigAppGrid {
            Layout.fillWidth: true
            columns: 8
            desktopEntries: root.pinnedEntries
            onEntryLaunched: root.entryLaunched()
        }

        WText {
            Layout.fillWidth: true
            visible: root.pinnedEntries.length === 0
            text: Translation.tr("Nothing is pinned to Start yet")
            color: Looks.colors.subfg
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
