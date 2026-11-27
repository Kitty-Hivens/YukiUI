import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// Search at the top. With nothing typed, the pinned applications and then all
// of them by name, as a grid. With something typed, what matches, as a list:
// Enter starts the highlighted one, the arrows move the highlight, the menu key
// opens its menu, Escape closes. A right click on any application opens its
// menu.
Item {
    id: root

    readonly property string query: search.text.trim()
    readonly property var results: root.query.length > 0 ? AppSearch.fuzzyQuery(root.query) : []
    readonly property var pinned: (Config.options?.launcher.pinnedApps ?? [])
        .map(id => DesktopEntries.byId(id))
        .filter(entry => entry)
    readonly property var everything: [...AppSearch.list]
        .filter(entry => !entry.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    function reset() {
        root.dismissMenu();
        search.text = "";
        appGrid.positionViewAtBeginning();
        search.input.forceActiveFocus();
    }

    function launch(entry) {
        if (!entry)
            return;
        AppLaunch.run(entry);
        ExStates.launcherOpen = false;
    }

    /** The menu of an application, opened at a point of the item given. */
    function openMenu(entry, item: Item, at: point) {
        if (!entry || !menu.parent)
            return;
        menu.popup(entry, item.mapToItem(menu, at.x, at.y));
    }

    function dismissMenu() {
        menu.dismiss();
    }

    implicitWidth: 640
    implicitHeight: 600

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ExLooks.spacing.xl
        spacing: ExLooks.spacing.l

        ExTextField {
            id: search

            Layout.fillWidth: true
            glyph: "search"
            placeholder: Translation.tr("Search apps")
            onTextChanged: resultList.currentIndex = 0

            input.Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    ExStates.launcherOpen = false;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.launch(root.results[resultList.currentIndex]);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    resultList.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    resultList.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    const row = resultList.currentItem;
                    if (row)
                        root.openMenu(row.modelData, row, Qt.point(ExLooks.spacing.xl, row.height));
                    event.accepted = true;
                }
            }
        }

        // Nothing typed: the grid. Only the tiles in sight are made, and made
        // again as it scrolls: all of them at once, a few hundred, took most
        // of the time the launcher spent coming up.
        GridView {
            id: appGrid

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.query.length === 0
            clip: true
            cellWidth: 96
            cellHeight: 92
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            model: root.everything

            ScrollBar.vertical: ScrollBar {}

            header: Column {
                width: appGrid.width
                spacing: ExLooks.spacing.s
                bottomPadding: ExLooks.spacing.s

                ExText {
                    visible: root.pinned.length > 0
                    text: Translation.tr("Pinned")
                    role: "label"
                }
                Grid {
                    visible: root.pinned.length > 0
                    columns: Math.max(1, Math.floor(appGrid.width / appGrid.cellWidth))
                    Repeater {
                        model: root.pinned
                        LauncherTile {
                            id: pinnedTile
                            required property var modelData
                            desktopEntry: modelData
                            onMenuRequested: at => root.openMenu(pinnedTile.desktopEntry, pinnedTile, at)
                        }
                    }
                }
                ExText {
                    topPadding: root.pinned.length > 0 ? ExLooks.spacing.m : 0
                    text: Translation.tr("All apps")
                    role: "label"
                }
            }

            delegate: LauncherTile {
                id: tile
                required property var modelData
                desktopEntry: modelData
                onMenuRequested: at => root.openMenu(tile.desktopEntry, tile, at)
            }
        }

        // Something typed: what matches.
        ListView {
            id: resultList

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.query.length > 0
            clip: true
            model: root.results
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            delegate: AbstractButton {
                id: row

                ExPrimaryOnly {
                    id: rowButtons
                    z: 1
                    onRightClicked: root.openMenu(row.modelData, row, Qt.point(rowButtons.mouseX, rowButtons.mouseY))
                }

                required property var modelData
                required property int index

                width: ListView.view.width
                implicitHeight: 52
                hoverEnabled: true
                onClicked: root.launch(row.modelData)

                background: Rectangle {
                    radius: ExLooks.radius.control
                    color: row.index === resultList.currentIndex ? ExLooks.colors.tonal : "transparent"

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: row.hovered
                        pressed: row.down
                    }
                }

                contentItem: RowLayout {
                    spacing: ExLooks.spacing.m

                    IconImage {
                        Layout.leftMargin: ExLooks.spacing.m
                        implicitSize: 32
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }
                    Column {
                        Layout.fillWidth: true
                        ExText {
                            width: parent.width
                            text: row.modelData.name
                        }
                        ExText {
                            width: parent.width
                            visible: text.length > 0
                            text: row.modelData.genericName || row.modelData.comment || ""
                            role: "caption"
                            dim: true
                        }
                    }
                }
            }

            ExText {
                anchors.centerIn: parent
                visible: root.query.length > 0 && root.results.length === 0
                text: Translation.tr("Nothing found")
                dim: true
            }
        }
    }

    // Over the whole window rather than the panel, so the panel's edge does
    // not cut it.
    LauncherMenu {
        id: menu
        parent: root.Window.window?.contentItem ?? null
        anchors.fill: parent
        returnFocus: search.input
    }
}
