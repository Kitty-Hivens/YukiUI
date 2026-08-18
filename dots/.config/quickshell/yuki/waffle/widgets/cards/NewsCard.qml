pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.waffle.looks
import qs.waffle.widgets
import qs.waffle

// News as one card among the rest, rather than the half of the board a publisher's
// feed occupies in the original. No reactions, no trends, no promoted anything --
// there is nothing behind those but the aggregator they came from.
WWidgetCard {
    id: root

    cardId: "news"
    title: Translation.tr("News")
    iconName: "news"
    readout: NewsFeed.articles.length > 0 ? `${NewsFeed.articles.length}` : ""
    visible: NewsFeed.enabled
    unpinnable: false // Switched on and off with the feed itself, not from here
    actionText: NewsFeed.articles.length > root.shownArticles ? Translation.tr("Show more") : ""
    onActionTriggered: root.shownArticles += 4

    property int shownArticles: 4

    WFlickable {
        id: storyList
        anchors {
            left: parent.left
            right: parent.right
        }
        implicitHeight: Math.min(stories.implicitHeight, Math.round(BoardLooks.unit * 18))
        contentWidth: width
        contentHeight: stories.implicitHeight
        clip: true

        ColumnLayout {
            id: stories
            width: storyList.width
            spacing: 8

            WText {
                Layout.fillWidth: true
                visible: NewsFeed.sources.length === 0
                text: Translation.tr("No feeds are configured")
                color: Looks.colors.subfg
            }

            WText {
                Layout.fillWidth: true
                visible: NewsFeed.sources.length > 0 && NewsFeed.articles.length === 0
                text: NewsFeed.loading ? Translation.tr("Fetching stories...") : Translation.tr("Nothing came back from the feeds")
                color: Looks.colors.subfg
            }

            Repeater {
                model: ScriptModel {
                    values: NewsFeed.articles.slice(0, root.shownArticles)
                }
                delegate: ArticleRow {
                    required property var modelData
                    article: modelData
                }
            }
        }
    }

    component ArticleRow: Rectangle {
        id: articleRow
        required property var article

        Layout.fillWidth: true
        implicitHeight: articleContent.implicitHeight + 16
        color: articleMouseArea.containsMouse ? Looks.colors.bg2Hover : "transparent"
        radius: Looks.radius.medium

        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        MouseArea {
            id: articleMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (articleRow.article.link)
                    Qt.openUrlExternally(articleRow.article.link);
                WStates.widgetsOpen = false;
            }
        }

        RowLayout {
            id: articleContent
            anchors {
                fill: parent
                margins: 8
            }
            spacing: 12

            StyledImage {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 52
                visible: (articleRow.article.image ?? "").length > 0
                source: articleRow.article.image ?? ""
                fillMode: Image.PreserveAspectCrop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                WText {
                    Layout.fillWidth: true
                    text: articleRow.article.title
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Looks.font.pixelSize.large
                }

                WText {
                    Layout.fillWidth: true
                    text: articleRow.article.source
                    color: Looks.colors.subfg
                    elide: Text.ElideRight
                }
            }
        }
    }
}
