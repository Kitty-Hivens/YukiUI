pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

WWidgetCard {
    id: root

    cardId: "todo"
    title: Translation.tr("To do")
    iconName: "checkmark"
    readout: `${Todo.list.length - root.unfinished.length}/${Todo.list.length}`

    readonly property list<var> unfinished: Todo.list.map((item, index) => ({
                item: item,
                index: index
            })).filter(entry => !entry.item.done)

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 2

        WText {
            Layout.fillWidth: true
            visible: root.unfinished.length === 0
            text: Translation.tr("Nothing left to do")
            color: Looks.colors.subfg
        }

        Repeater {
            model: ScriptModel {
                values: root.unfinished.slice(0, 5)
            }
            delegate: RowLayout {
                id: taskRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 10

                WPanelIconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    iconSize: 16
                    iconName: "checkmark"
                    onClicked: Todo.markDone(taskRow.modelData.index)
                }

                WText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: taskRow.modelData.item.content
                    elide: Text.ElideRight
                }
            }
        }

        WText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.unfinished.length > 5
            text: Translation.tr("+%1 more").arg(root.unfinished.length - 5)
            color: Looks.colors.subfg
        }
    }
}
