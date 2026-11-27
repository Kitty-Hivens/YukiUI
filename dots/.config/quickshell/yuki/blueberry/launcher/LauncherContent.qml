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
// of them by name, as a grid. With something typed, what matches, as a list.
// The keyboard stays with the search field throughout: the arrows move the pick,
// in the grid or the list, Enter starts it, the menu key opens its menu, and
// Escape clears what was typed, then closes. A right click on any application
// opens its menu.
Item {
    id: root

    readonly property string query: search.text.trim()
    readonly property var results: root.query.length > 0 ? AppSearch.fuzzyQuery(root.query) : []
    // Read again as applications come and go, not only as the pins change:
    // kept built, the launcher is no longer made anew to catch up.
    readonly property var pinned: {
        AppSearch.list;
        return (Config.options?.launcher.pinnedApps ?? [])
            .map(id => DesktopEntries.byId(id))
            .filter(entry => entry);
    }
    readonly property var everything: [...AppSearch.list]
        .filter(entry => !entry.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    /**
     * The application picked with the arrows with nothing typed: the pinned
     * ones first, then the grid, as one run. -1 before an arrow is pressed.
     */
    property int pick: -1
    readonly property int columns: Math.max(1, Math.floor(appGrid.width / appGrid.cellWidth))
    readonly property int total: root.pinned.length + root.everything.length

    function picked() {
        if (root.pick < 0)
            return null;
        return root.pick < root.pinned.length ? root.pinned[root.pick] : root.everything[root.pick - root.pinned.length] ?? null;
    }

    /** Moves the pick on the grid by a step, in rows of the grid within each part. */
    function movePick(dx: int, dy: int) {
        if (root.total === 0)
            return;
        if (root.pick < 0) {
            root.pick = 0;
        } else if (dx !== 0) {
            root.pick = Math.max(0, Math.min(root.total - 1, root.pick + dx));
        } else {
            const pins = root.pinned.length;
            const inPins = root.pick < pins;
            const column = (inPins ? root.pick : root.pick - pins) % root.columns;
            if (dy > 0) {
                const next = root.pick + root.columns;
                // Off the bottom of the pinned rows into the grid's first row.
                root.pick = inPins && next >= pins ? Math.min(root.total - 1, pins + column) : Math.min(root.total - 1, next);
            } else {
                const previous = root.pick - root.columns;
                if (!inPins && previous < pins && pins > 0) {
                    // Up from the grid's first row into the last pinned row.
                    const lastRow = Math.floor((pins - 1) / root.columns) * root.columns;
                    root.pick = Math.min(pins - 1, lastRow + column);
                } else {
                    root.pick = Math.max(0, previous);
                }
            }
        }
        if (root.pick < root.pinned.length)
            appGrid.positionViewAtBeginning();
        else
            appGrid.positionViewAtIndex(root.pick - root.pinned.length, GridView.Contain);
    }

    /** The item standing for the pick, to open its menu at. */
    function pickedItem(): Item {
        if (root.pick < 0)
            return null;
        if (root.pick < root.pinned.length)
            return pinnedTiles.itemAt(root.pick);
        return appGrid.itemAtIndex(root.pick - root.pinned.length);
    }

    function reset() {
        root.dismissMenu();
        root.pick = -1;
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
            onTextChanged: {
                resultList.currentIndex = 0;
                root.pick = -1;
            }

            input.Keys.onPressed: event => {
                const searching = root.query.length > 0;
                const menuKey = event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier));
                if (event.key === Qt.Key_Escape) {
                    // What was typed goes first, then the launcher.
                    if (search.text.length > 0)
                        search.text = "";
                    else
                        ExStates.launcherOpen = false;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    // Nowhere else to go: the field keeps the keyboard.
                } else if (searching) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.launch(root.results[resultList.currentIndex]);
                    else if (event.key === Qt.Key_Down)
                        resultList.incrementCurrentIndex();
                    else if (event.key === Qt.Key_Up)
                        resultList.decrementCurrentIndex();
                    else if (menuKey) {
                        const row = resultList.currentItem;
                        if (row)
                            root.openMenu(row.modelData, row, Qt.point(ExLooks.spacing.xl, row.height));
                    } else
                        return;
                } else {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.launch(root.picked());
                    else if (event.key === Qt.Key_Down)
                        root.movePick(0, 1);
                    else if (event.key === Qt.Key_Up)
                        root.movePick(0, -1);
                    // Left and right move the pick only once one is picked:
                    // before that they move the cursor in the field as usual.
                    else if (event.key === Qt.Key_Right && root.pick >= 0)
                        root.movePick(1, 0);
                    else if (event.key === Qt.Key_Left && root.pick >= 0)
                        root.movePick(-1, 0);
                    else if (menuKey) {
                        const tile = root.pickedItem();
                        if (tile)
                            root.openMenu(root.picked(), tile, Qt.point(tile.width / 2, tile.height / 2));
                    } else
                        return;
                }
                event.accepted = true;
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
                    columns: root.columns
                    Repeater {
                        id: pinnedTiles
                        model: root.pinned
                        LauncherTile {
                            id: pinnedTile
                            required property var modelData
                            required property int index
                            desktopEntry: modelData
                            current: root.pick === pinnedTile.index
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
                required property int index
                desktopEntry: modelData
                current: root.pick === root.pinned.length + tile.index
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
                focusPolicy: Qt.NoFocus
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
