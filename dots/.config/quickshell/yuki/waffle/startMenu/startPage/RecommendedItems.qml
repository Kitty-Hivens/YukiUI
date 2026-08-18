pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.waffle.looks
import qs.waffle

/**
 * What the start menu suggests: the applications that arrived lately, then the
 * files that were opened lately.
 *
 * Measured. Two columns of 268 by 56 with 20 between them, which fills the 576 the
 * page leaves exactly. The icon sits 12 in from the item's own edge, which lands it
 * on the same 64 from the menu's edge as every heading on the page.
 */
GridLayout {
    id: root

    columns: 2
    columnSpacing: 20
    rowSpacing: 0

    /// Applications first, then files, which is the order the reference shows them
    /// in. Either half can be switched off, and with both off the section is empty
    /// and the page leaves it out.
    readonly property var items: {
        const out = [];
        if (Config.options.waffles.startMenu.showRecentlyAdded)
            for (const entry of RecentApps.entries)
                out.push({
                    application: entry,
                    url: "",
                    name: entry.name,
                    caption: Translation.tr("Recently added"),
                    icon: entry.icon
                });
        if (Config.options.waffles.startMenu.showRecentFiles)
            for (const file of RecentFiles.entries)
                out.push({
                    application: null,
                    url: file.url,
                    name: file.name,
                    caption: file.directory,
                    icon: ""
                });
        return out.slice(0, 6);
    }

    Repeater {
        model: root.items
        delegate: RecommendedItem {
            required property var modelData
            item: modelData
        }
    }

    component RecommendedItem: Rectangle {
        id: recommendedItem
        required property var item

        implicitWidth: 268
        implicitHeight: 56
        radius: Looks.radius.medium
        color: mouseArea.pressed ? Looks.colors.bg2Active : mouseArea.containsMouse ? Looks.colors.bg2 : "transparent"
        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        Item {
            id: itemIcon
            anchors {
                left: parent.left
                leftMargin: 12
                verticalCenter: parent.verticalCenter
            }
            implicitWidth: 32
            implicitHeight: 32

            /// An application brings its own picture, which comes from the icon theme
            /// and is drawn as it is. A file brings none, so it gets the one glyph
            /// that says "a document" -- a Fluent one, drawn in the foreground colour
            /// like every other glyph, which is a different path through the assets.
            WAppIcon {
                anchors.centerIn: parent
                visible: !!recommendedItem.item.application
                implicitSize: 32
                iconName: recommendedItem.item.icon
                tryCustomIcon: false
            }

            FluentIcon {
                anchors.centerIn: parent
                visible: !recommendedItem.item.application
                implicitSize: 24
                icon: "document"
            }
        }

        ColumnLayout {
            anchors {
                left: itemIcon.right
                leftMargin: 12
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 0

            WText {
                Layout.fillWidth: true
                text: recommendedItem.item.name
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            WText {
                Layout.fillWidth: true
                text: recommendedItem.item.caption
                font.pixelSize: 12
                color: Looks.colors.subfg
                elide: Text.ElideMiddle
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (recommendedItem.item.application)
                    recommendedItem.item.application.execute();
                else
                    Qt.openUrlExternally(recommendedItem.item.url);
                WStates.searchOpen = false;
            }
        }
    }
}
