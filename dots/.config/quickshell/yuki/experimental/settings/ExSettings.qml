pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// The settings window's content, laid out as Windows 11 lays out its own: who
// is signed in, a search and the categories down the left, and on the right
// the path to the page, its title and the page itself.
Item {
    id: root

    /** The page to open on: a page's key or a category's, or empty for home. */
    property string startPage: ""
    /** Set by the display page, so closing the window knows there may be a
     *  layout waiting to be kept that has to be taken back. */
    property bool displaysTouched: false

    property string categoryKey: "home"
    /** A page within the category, or empty for the category's own page. */
    property string pageKey: ""
    readonly property string query: search.text.trim()

    readonly property var category: catalogue.category(root.categoryKey)
    readonly property var page: root.pageKey.length > 0 ? catalogue.page(root.pageKey) : null

    function open(key: string) {
        search.text = "";
        const page = catalogue.page(key);
        if (page) {
            root.categoryKey = page.category;
            root.pageKey = page.key;
        } else if (catalogue.category(key)) {
            root.categoryKey = key;
            root.pageKey = "";
        } else {
            root.categoryKey = "home";
            root.pageKey = "";
        }
    }

    Component.onCompleted: root.open(root.startPage)

    SettingsCatalogue {
        id: catalogue
    }

    ShellLink {
        id: shellLink
        watching: root.Window.active
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Who is signed in, the search, and the categories.
        ColumnLayout {
            // Fixed: its rows fill its width, which would otherwise have it
            // take the window's width from the page.
            Layout.fillWidth: false
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            Layout.margins: ExLooks.spacing.m
            Layout.rightMargin: 0
            spacing: ExLooks.spacing.m

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                Layout.leftMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.m

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: ExLooks.colors.tonal

                    ExText {
                        anchors.centerIn: parent
                        text: (SystemInfo.username || "?").charAt(0).toUpperCase()
                        font.pixelSize: 24
                        font.weight: 600
                        color: ExLooks.colors.tonalInk
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: SystemInfo.username
                        font.weight: ExLooks.font.weightTitle
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: Translation.tr("Local account")
                        role: "caption"
                        dim: true
                    }
                }
            }

            ExTextField {
                id: search

                Layout.fillWidth: true
                glyph: "search"
                placeholder: Translation.tr("Find a setting")
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: catalogue.categories

                delegate: AbstractButton {
                    id: navItem

                    ExPrimaryOnly {
                        z: 1
                    }

                    required property var modelData
                    readonly property bool here: root.query.length === 0 && navItem.modelData.key === root.categoryKey

                    width: ListView.view.width
                    implicitHeight: 40
                    hoverEnabled: true
                    onClicked: root.open(navItem.modelData.key)

                    background: Rectangle {
                        radius: ExLooks.radius.menuItem
                        color: navItem.here ? ExLooks.colors.tonal : "transparent"

                        ExStateLayer {
                            ink: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            hovered: navItem.hovered
                            pressed: navItem.down
                        }
                    }
                    contentItem: RowLayout {
                        spacing: ExLooks.spacing.m

                        ExGlyph {
                            Layout.leftMargin: ExLooks.spacing.m
                            text: navItem.modelData.glyph
                            size: 20
                            fill: navItem.here ? 1 : 0
                            color: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: navItem.modelData.name
                            color: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            font.weight: navItem.here ? ExLooks.font.weightLabel : ExLooks.font.weightBody
                        }
                    }
                }
            }
        }

        // The path, the title and the page.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Category, then the page within it, the category going back.
            Row {
                Layout.leftMargin: ExLooks.spacing.xl + ExLooks.spacing.l
                Layout.topMargin: ExLooks.spacing.xl
                Layout.bottomMargin: ExLooks.spacing.m
                spacing: ExLooks.spacing.s

                AbstractButton {
                    id: crumb

                    ExPrimaryOnly {
                        z: 1
                    }

                    readonly property bool leads: root.page !== null && root.query.length === 0

                    anchors.verticalCenter: parent.verticalCenter
                    enabled: crumb.leads
                    hoverEnabled: true
                    onClicked: root.open(root.categoryKey)

                    contentItem: ExText {
                        text: root.query.length > 0 ? Translation.tr("Search") : (root.category?.name ?? "")
                        font.pixelSize: 28
                        font.weight: ExLooks.font.weightTitle
                        color: crumb.leads && !crumb.hovered ? ExLooks.colors.textDim : ExLooks.colors.text
                    }
                    background: null
                }
                ExGlyph {
                    visible: crumb.leads
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    size: 24
                    color: ExLooks.colors.textDim
                }
                ExText {
                    visible: crumb.leads
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.page?.name ?? ""
                    font.pixelSize: 28
                    font.weight: ExLooks.font.weightTitle
                }
            }

            Flickable {
                id: scroller

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: pageHolder.implicitHeight + ExLooks.spacing.xl
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // No wider than a line can be read at, as on Windows.
                Item {
                    id: pageHolder

                    x: ExLooks.spacing.xl + ExLooks.spacing.l
                    width: Math.min(1000, scroller.width - 2 * x)
                    implicitHeight: pageLoader.item?.implicitHeight ?? 0

                    Loader {
                        id: pageLoader

                        width: parent.width
                        // A new page starts at its top.
                        onLoaded: scroller.contentY = 0

                        readonly property string source_: root.query.length > 0 ? "SearchPage.qml"
                            : root.page ? (root.page.component ?? "NotYetPage.qml")
                            : (root.category?.component ?? "CategoryPage.qml")
                        onSource_Changed: pageLoader.setSource(Qt.resolvedUrl(pageLoader.source_), {
                            settings: root,
                            catalogue: catalogue,
                            shell: shellLink
                        })
                        Component.onCompleted: pageLoader.setSource(Qt.resolvedUrl(pageLoader.source_), {
                            settings: root,
                            catalogue: catalogue,
                            shell: shellLink
                        })
                    }
                }
            }
        }
    }
}
