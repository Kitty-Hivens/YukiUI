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
    readout: "W" + root.weekNumber

    readonly property var locale: Qt.locale(Config.options.calendar.locale)
    // ISO week: Thursday of the current week decides which year's week this is.
    readonly property int weekNumber: {
        const date = new Date(DateTime.clock.date.getFullYear(), DateTime.clock.date.getMonth(), DateTime.clock.date.getDate());
        const dayIndex = (date.getDay() + 6) % 7;
        date.setDate(date.getDate() - dayIndex + 3);
        const firstThursday = new Date(date.getFullYear(), 0, 4);
        const firstDayIndex = (firstThursday.getDay() + 6) % 7;
        firstThursday.setDate(firstThursday.getDate() - firstDayIndex + 3);
        return 1 + Math.round((date.getTime() - firstThursday.getTime()) / (7 * 24 * 60 * 60 * 1000));
    }
    readonly property int dayCellSize: 36
    readonly property int gridWidth: dayCellSize * 7 + 4 * 6

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

        // Both rows are laid out to the same fixed width and centred: letting either
        // stretch on its own put the day names out of step with the columns under them.
        DayOfWeekRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.gridWidth
            locale: root.locale
            spacing: monthGrid.buttonSpacing
            padding: 0
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
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.gridWidth
            locale: root.locale
            verticalPadding: 0
            buttonSize: root.dayCellSize
            buttonSpacing: 4
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
