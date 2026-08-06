pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.widgets

WWidgetCard {
    id: root

    cardId: "calendar"
    title: Qt.locale().toString(DateTime.clock.date, "MMMM yyyy")
    iconName: "calendar-add"

    readonly property var locale: Qt.locale(Config.options.calendar.locale)

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 6

        WText {
            Layout.fillWidth: true
            text: Qt.locale().toString(DateTime.clock.date, "dddd, d")
            font.pixelSize: Looks.font.pixelSize.larger
            font.weight: Looks.font.weight.strong
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: root.locale
            spacing: monthGrid.buttonSpacing
            delegate: Item {
                id: dayOfWeekItem
                required property var model
                implicitHeight: monthGrid.buttonSize
                implicitWidth: monthGrid.buttonSize
                WText {
                    anchors.centerIn: parent
                    text: dayOfWeekItem.model.shortName.substring(0, 2)
                    color: Looks.colors.subfg
                }
            }
        }

        CalendarView {
            id: monthGrid
            Layout.fillWidth: true
            locale: root.locale
            verticalPadding: 0
            buttonSize: 30
            buttonSpacing: 2
            buttonVerticalSpacing: 1
            delegate: Item {
                id: dayItem
                required property var model
                implicitWidth: monthGrid.buttonSize
                implicitHeight: monthGrid.buttonSize

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: monthGrid.buttonSize - 4
                    implicitHeight: implicitWidth
                    radius: height / 2
                    color: dayItem.model.today ? Looks.colors.accent : "transparent"
                }

                WText {
                    anchors.centerIn: parent
                    text: dayItem.model.day
                    color: dayItem.model.today ? Looks.colors.accentFg : (dayItem.model.month === monthGrid.focusedMonth ? Looks.colors.fg : Looks.colors.subfg)
                }
            }
        }
    }
}
