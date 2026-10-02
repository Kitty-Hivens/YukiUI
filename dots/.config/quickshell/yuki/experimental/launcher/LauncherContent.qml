import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.looks

// Search at the top. With nothing typed, the pinned applications and then all
// of them by name, as a grid. With something typed, what matches, as a list:
// Enter starts the highlighted one, the arrows move the highlight, Escape closes.
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
        search.text = "";
        search.input.forceActiveFocus();
    }

    function launch(entry) {
        if (!entry)
            return;
        entry.execute();
        ExStates.launcherOpen = false;
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
                }
            }
        }

        // Nothing typed: the grid.
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.query.length === 0
            clip: true
            contentHeight: grids.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: grids
                width: parent.width
                spacing: ExLooks.spacing.s

                ExText {
                    visible: root.pinned.length > 0
                    text: Translation.tr("Pinned")
                    role: "label"
                }
                Grid {
                    visible: root.pinned.length > 0
                    columns: 6
                    Repeater {
                        model: root.pinned
                        LauncherTile {
                            required property var modelData
                            desktopEntry: modelData
                        }
                    }
                }

                ExText {
                    topPadding: root.pinned.length > 0 ? ExLooks.spacing.m : 0
                    text: Translation.tr("All apps")
                    role: "label"
                }
                Grid {
                    columns: 6
                    Repeater {
                        model: root.everything
                        LauncherTile {
                            required property var modelData
                            desktopEntry: modelData
                        }
                    }
                }
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
                    z: 1
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
}
