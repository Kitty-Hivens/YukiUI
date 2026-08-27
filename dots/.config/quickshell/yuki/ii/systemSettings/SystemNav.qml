pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.common

/**
 * Section grouped navigation. A flat list of twenty entries exceeds what anyone
 * scans comfortably, so entries are chunked under headings and search offers a
 * direct path past the hierarchy.
 *
 * The window title bar carries the app identity; repeating it here would put
 * three headings above the first control.
 */
Rectangle {
    id: root
    property var groups: []
    property string currentComponent: ""

    signal pageSelected(string component)

    // Matched the way the launcher matches, so a half remembered or mistyped
    // name still finds the page instead of returning nothing -- and against what
    // a page is about as well as what it is called, because the words somebody
    // types are the ones inside the page rather than the eight on the rail.
    readonly property var searchable: {
        const flat = [];
        for (const group of root.groups)
            for (const page of group.pages)
                flat.push({
                    name: page.name,
                    description: page.description,
                    keywords: page.keywords,
                    icon: page.icon,
                    component: page.component
                });
        return flat;
    }

    readonly property var rows: {
        const query = searchField.text.trim();
        if (query.length === 0) {
            const out = [];
            for (const group of root.groups) {
                // An unnamed group is a plain run of entries, not a section:
                // the way into the settings needs no heading over one row.
                if (group.name.length > 0)
                    out.push({ section: true, name: group.name });
                for (const page of group.pages)
                    out.push({ section: false, name: page.name, icon: page.icon, component: page.component });
            }
            return out;
        }
        return Fuzzy.go(query, root.searchable, { all: false, keys: ["name", "description", "keywords"] })
            .map(result => Object.assign({ section: false }, result.obj));
    }

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.normal
    implicitWidth: 260

    function clearSearchFocus() {
        if (searchField.activeFocus)
            root.forceActiveFocus();
    }

    // Sits under the content, so clicks that miss a control still land here and
    // release the search field rather than leaving it focused forever.
    MouseArea {
        anchors.fill: parent
        onPressed: root.clearSearchFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.topMargin: 2
            placeholderText: Translation.tr("Search settings")

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    searchField.text = "";
                    root.forceActiveFocus();
                    event.accepted = true;
                }
            }
        }

        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.rows

            delegate: Loader {
                required property var modelData
                anchors {
                    left: parent?.left
                    right: parent?.right
                }
                sourceComponent: modelData.section ? sectionLabel : pageButton

                Component {
                    id: sectionLabel
                    Item {
                        implicitHeight: 34
                        StyledText {
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                bottom: parent.bottom
                                bottomMargin: 6
                            }
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Component {
                    id: pageButton
                    RippleButton {
                        id: navButton
                        readonly property bool current: root.currentComponent === modelData.component
                        // Only a search result carries one. A rail of eight names
                        // needs no explaining; a result that matched on a word
                        // inside the page does.
                        readonly property string subtitle: modelData.description ?? ""
                        implicitHeight: navButton.subtitle.length > 0 ? 54 : 42
                        buttonRadius: height / 2
                        toggled: navButton.current
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            root.clearSearchFocus();
                            root.pageSelected(modelData.component);
                        }

                        contentItem: RowLayout {
                            spacing: 12
                            MaterialSymbol {
                                Layout.leftMargin: 8
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.larger
                                fill: navButton.current ? 1 : 0
                                color: navButton.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: navButton.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: navButton.subtitle.length > 0
                                    horizontalAlignment: Text.AlignLeft
                                    text: navButton.subtitle
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
