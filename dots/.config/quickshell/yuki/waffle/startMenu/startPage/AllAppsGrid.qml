pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

GridLayout {
    id: root

    // Three, not four. Measured: the cards are 156 and sit 64 in from either edge
    // of a 640 menu, which leaves exactly 512 for three of them and their gaps.
    // Four fitted only while the menu was mistakenly 832 wide.
    columns: 3

    // Every category grid filters this same list, so the sort happens here once
    // rather than in each of them.
    readonly property list<DesktopEntry> sortedEntries: [...DesktopEntries.applications.values].sort((a, b) => a.name.localeCompare(b.name))

    Component {
        id: aggAppCatComp
        AggregatedAppCategoryModel {}
    }
    property list<AggregatedAppCategoryModel> aggregatedCategories: [
        aggAppCatComp.createObject(null, {
            name: Translation.tr("Productivity"),
            categories: ["Development", "Education", "Network", "Office"]
        }), aggAppCatComp.createObject(null, {
            name: Translation.tr("Utilities & Tools"),
            categories: ["Utility", "Science"]
        }), aggAppCatComp.createObject(null, {
            name: Translation.tr("Creativity"),
            categories: ["AudioVideo", "Graphics"]
        }), aggAppCatComp.createObject(null, {
            name: Translation.tr("System"),
            categories: ["Settings", "System"]
        }), aggAppCatComp.createObject(null, {
            name: Translation.tr("Other"),
            categories: ["Game"]
        }), 
    ]

    Repeater {
        model: root.aggregatedCategories
        delegate: AppCategory {
            required property var modelData
            aggregatedCategory: modelData
        }
    }

    columnSpacing: 22
    rowSpacing: 12
    component AppCategory: Item {
        id: categoryItem
        property AggregatedAppCategoryModel aggregatedCategory
        implicitWidth: categoryLayout.implicitWidth
        implicitHeight: categoryLayout.implicitHeight
        ColumnLayout {
            id: categoryLayout
            anchors.fill: parent
            spacing: 4

            AppCategoryGrid {
                id: categoryGrid
                Layout.fillWidth: true
                aggregatedCategory: categoryItem.aggregatedCategory
                allEntries: root.sortedEntries
            }

            WButton {
                id: categoryButton
                Layout.fillWidth: true
                implicitHeight: 32

                contentItem: WText {
                    id: categoryButtonText
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: categoryItem.aggregatedCategory.name
                }
                onClicked: {
                    categoryGrid.openCategoryFolder();
                }
            }
        }
    }
}
