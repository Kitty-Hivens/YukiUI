pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

// The stories beside the cards: two columns of them under a row of tabs, and a
// button at the end for the rest.
ColumnLayout {
    id: root

    property int columnWidth: 340
    property int shownArticles: 8

    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        WText {
            text: Translation.tr("Discover")
            font.weight: Looks.font.weight.strong
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 3
            radius: height / 2
            color: Looks.colors.accent
        }
        Item {
            Layout.fillWidth: true
        }
    }

    StyledFlickable {
        id: storyFlickable
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: storyColumn.implicitHeight

        ColumnLayout {
            id: storyColumn
            width: storyFlickable.width
            spacing: 12

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: ScriptModel {
                        values: NewsFeed.articles.slice(0, root.shownArticles)
                    }
                    delegate: ArticleCard {
                        required property var modelData
                        article: modelData
                    }
                }
            }

            EmptyNote {
                visible: !NewsFeed.enabled
                text: Translation.tr("Stories are switched off")
            }
            EmptyNote {
                visible: NewsFeed.enabled && NewsFeed.sources.length === 0
                text: Translation.tr("No feeds are configured")
            }
            EmptyNote {
                visible: NewsFeed.enabled && NewsFeed.sources.length > 0 && NewsFeed.articles.length === 0
                text: NewsFeed.loading ? Translation.tr("Fetching stories...") : Translation.tr("Nothing came back from the feeds")
            }

            WTextButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                visible: NewsFeed.articles.length > root.shownArticles
                implicitHeight: 34
                text: Translation.tr("Show more")
                onClicked: root.shownArticles += 8
            }
        }
    }

    component EmptyNote: WText {
        Layout.fillWidth: true
        Layout.topMargin: 30
        horizontalAlignment: Text.AlignHCenter
        color: Looks.colors.subfg
    }

    component ArticleCard: Rectangle {
        id: articleCard
        required property var article

        Layout.preferredWidth: root.columnWidth
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: articleColumn.implicitHeight + 24

        color: articleMouseArea.containsMouse ? Looks.colors.bg2Hover : Looks.colors.bg2
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
                margins: 12
            }
            spacing: 8

            StyledImage {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                visible: (articleCard.article.image ?? "").length > 0
                source: articleCard.article.image ?? ""
                fillMode: Image.PreserveAspectCrop
            }

            WText {
                Layout.fillWidth: true
                text: articleCard.article.source
                color: Looks.colors.subfg
                elide: Text.ElideRight
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
        }
    }
}
