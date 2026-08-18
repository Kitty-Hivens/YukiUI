pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.waffle.looks

// What the panel shows before anything is typed: the searches last made, to pick
// one up again.
BodyRectangle {
    id: root

    signal queryChosen(string query)

    readonly property list<string> queries: Persistent.states.search.recentQueries

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 32
            rightMargin: 32
            topMargin: 25
            bottomMargin: 30
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            WText {
                Layout.fillWidth: true
                text: Translation.tr("Recent")
                font.pixelSize: Looks.font.pixelSize.large
                font.weight: Looks.font.weight.stronger
            }

            WTextButton {
                visible: root.queries.length > 0
                implicitHeight: 30
                text: Translation.tr("Clear")
                onClicked: {
                    Persistent.states.search.recentQueries = [];
                }
            }
        }

        WText {
            Layout.fillWidth: true
            visible: root.queries.length === 0
            text: Translation.tr("Searches you make will show up here")
            color: Looks.colors.subfg
        }

        WListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2

            model: ScriptModel {
                values: root.queries
            }

            delegate: WButton {
                id: queryButton
                required property var modelData
                width: ListView.view?.width
                horizontalAlignment: Text.AlignLeft
                implicitHeight: 40
                icon.name: "arrow-counterclockwise" // The set has no clock-face history icon
                text: queryButton.modelData
                onClicked: root.queryChosen(queryButton.modelData)
            }
        }
    }
}
