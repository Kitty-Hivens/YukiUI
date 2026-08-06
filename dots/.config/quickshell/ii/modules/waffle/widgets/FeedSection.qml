pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

// The stories half of the board. Folded away behind a button, the way the board
// this copies keeps it, and absent altogether while no feeds are configured.
ColumnLayout {
    id: root

    property bool expanded: false

    spacing: 12
    visible: NewsFeed.enabled

    WTextButton {
        Layout.alignment: Qt.AlignHCenter
        implicitHeight: 34
        text: root.expanded ? Translation.tr("Fewer stories") : Translation.tr("More stories")
        onClicked: root.expanded = !root.expanded
    }

    WText {
        Layout.fillWidth: true
        visible: root.expanded && NewsFeed.sources.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("No feeds are configured")
        color: Looks.colors.subfg
    }

    WText {
        Layout.fillWidth: true
        visible: root.expanded && NewsFeed.loading && NewsFeed.articles.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("Fetching stories...")
        color: Looks.colors.subfg
    }

    Repeater {
        model: ScriptModel {
            values: root.expanded ? NewsFeed.articles : []
        }
        delegate: ArticleCard {
            required property var modelData
            article: modelData
        }
    }

    component ArticleCard: Rectangle {
        id: articleCard
        required property var article

        Layout.fillWidth: true
        implicitHeight: articleColumn.implicitHeight + 32
        color: articleMouseArea.containsMouse ? Looks.colors.bg1Hover : Looks.colors.bg1
        radius: Looks.radius.large
        border.width: 1
        border.color: Looks.colors.bg2Border

        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        MouseArea {
            id: articleMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (articleCard.article.link)
                    Qt.openUrlExternally(articleCard.article.link);
                GlobalStates.widgetsOpen = false;
            }
        }

        ColumnLayout {
            id: articleColumn
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 8

            StyledImage {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                visible: (articleCard.article.image ?? "").length > 0
                source: articleCard.article.image ?? ""
                fillMode: Image.PreserveAspectCrop
            }

            WText {
                Layout.fillWidth: true
                text: articleCard.article.title
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pixelSize: Looks.font.pixelSize.large
                font.weight: Looks.font.weight.strong
            }

            WText {
                Layout.fillWidth: true
                text: articleCard.article.source
                color: Looks.colors.subfg
                elide: Text.ElideRight
            }
        }
    }
}
