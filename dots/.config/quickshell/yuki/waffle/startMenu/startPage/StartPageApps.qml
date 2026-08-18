pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks

BodyRectangle {
    id: root

    /// One scrolling page. Measured: the sections travel with the page rather than
    /// their headings sticking to the top, and the only things that hold still are the
    /// search field above this body and the account bar below it -- neither of which
    /// is here. Before this the page was a fixed column, and whatever did not fit was
    /// simply cut off at the bottom edge.
    Flickable {
        id: pageFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.y + pageColumn.implicitHeight + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Over the page rather than beside it: the sections stop 64 in from the edge,
        // which leaves the scrollbar its own room without the column giving any up.
        ScrollBar.vertical: WScrollBar {}

        ColumnLayout {
            id: pageColumn
            x: 32
            y: 25
            width: pageFlickable.width - pageColumn.x * 2
            spacing: 26

            PinnedApps {
                Layout.fillWidth: true
            }

            Recommended {
                Layout.fillWidth: true
            }

            AllApps {
                Layout.fillWidth: true
            }
        }
    }

    component PinnedApps: PageSection {
        title: Translation.tr("Pinned")

        BigAppGrid {
            Layout.fillWidth: true
            // Six 96-wide cells fill the 576 left between the menu's 32 margins exactly,
            // which is how Windows lays the grid out. Eight only ever fitted the width
            // this menu had before it was measured.
            columns: 6
            // Looked up the way a window class is, and only the ones that were found
            // are handed on. A pin to an application that is not installed came back
            // as nothing and went into the grid as it was, where the button that
            // renders it reads a name and an icon off it straight away.
            desktopEntries: Config.options.launcher.pinnedApps
                .map(appId => AppSearch.entryFor(appId))
                .filter(entry => entry !== null)
            onEntryLaunched: GlobalStates.searchOpen = false
        }
    }

    component Recommended: PageSection {
        title: Translation.tr("Recommended")
        // Nothing has arrived and nothing has been opened, or both halves are switched
        // off: the reference does not leave a heading over empty space, so nor does
        // this. The whole section goes, heading and all.
        visible: recommendedItems.items.length > 0

        RecommendedItems {
            id: recommendedItems
            // 20 in from the page's own margin, which is where the reference starts
            // the row; the pair then reaches the far side exactly.
            Layout.leftMargin: 20
        }
    }

    component AllApps: PageSection {
        title: Translation.tr("All")
        // TODO: Do we wanna also implement list view and grid view?
        //       (instead of only category view)
        AllAppsGrid {
            Layout.fillWidth: true
            // A further 32 on top of the page's own, which is what puts the cards 64
            // in from the menu's edge where they were measured.
            Layout.leftMargin: 32
            Layout.rightMargin: 32
        }
    }

    component PageSection: ColumnLayout {
        id: pageSection
        required property string title
        default property alias pageData: pageSectionContentArea.data

        spacing: 16

        WText {
            Layout.leftMargin: 32
            text: pageSection.title
            font.pixelSize: Looks.font.pixelSize.large
            font.weight: Looks.font.weight.stronger
        }

        ColumnLayout {
            id: pageSectionContentArea
            Layout.fillWidth: true
        }
    }
}
