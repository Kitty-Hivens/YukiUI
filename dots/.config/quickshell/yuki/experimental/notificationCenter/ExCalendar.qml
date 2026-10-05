import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// A month, in the shell's language and with its weeks starting where that
// language starts them. Today is marked, the arrows turn the months, and the
// month's name brings back the current one.
ColumnLayout {
    id: root

    readonly property var locale: Qt.locale(Translation.languageCode || Qt.locale().name)
    property var today: new Date()
    property int year: root.today.getFullYear()
    property int month: root.today.getMonth()

    readonly property int firstDay: root.locale.firstDayOfWeek % 7
    readonly property string title: {
        const name = root.locale.standaloneMonthName(root.month, Locale.LongFormat);
        return `${name.charAt(0).toUpperCase()}${name.slice(1)} ${root.year}`;
    }
    readonly property var days: {
        const first = new Date(root.year, root.month, 1);
        const lead = (first.getDay() - root.firstDay + 7) % 7;
        const cells = [];
        for (let i = 0; i < 42; i++)
            cells.push(new Date(root.year, root.month, 1 - lead + i));
        return cells;
    }

    // The month the calendar is on its way to. The one on show changes only
    // halfway through the scroll, and a second click before then turned to
    // the same month as the first.
    readonly property int aimedYear: scroll.running ? root.pendingYear : root.year
    readonly property int aimedMonth: scroll.running ? root.pendingMonth : root.month

    function turn(step: int) {
        const target = new Date(root.aimedYear, root.aimedMonth + step, 1);
        root.show(target.getFullYear(), target.getMonth(), step);
    }

    function backToToday() {
        const step = Math.sign((root.today.getFullYear() - root.aimedYear) * 12 + root.today.getMonth() - root.aimedMonth);
        root.show(root.today.getFullYear(), root.today.getMonth(), step);
    }

    // The month on show scrolls out the way the arrow points and the next one
    // comes in behind it, the way the Windows calendar scrolls.
    property int pendingYear: 0
    property int pendingMonth: 0
    property int direction: 1

    function show(year: int, month: int, step: int) {
        if (step === 0 || (year === root.aimedYear && month === root.aimedMonth))
            return;
        root.pendingYear = year;
        root.pendingMonth = month;
        root.direction = step > 0 ? 1 : -1;
        scroll.restart();
    }

    SequentialAnimation {
        id: scroll

        ParallelAnimation {
            NumberAnimation {
                target: monthGrid
                property: "y"
                to: -root.direction * 48
                duration: ExLooks.motion.fast
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: monthGrid
                property: "opacity"
                to: 0
                duration: ExLooks.motion.fast
            }
        }
        ScriptAction {
            script: {
                root.year = root.pendingYear;
                root.month = root.pendingMonth;
                monthGrid.y = root.direction * 48;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: monthGrid
                property: "y"
                to: 0
                duration: ExLooks.motion.normal
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: monthGrid
                property: "opacity"
                to: 1
                duration: ExLooks.motion.normal
            }
        }
    }

    spacing: ExLooks.spacing.xs

    // The date moves on at midnight while the shell runs for days.
    Connections {
        target: DateTime
        function onShortDateChanged() {
            const wasCurrent = root.year === root.today.getFullYear() && root.month === root.today.getMonth();
            root.today = new Date();
            if (wasCurrent) {
                root.year = root.today.getFullYear();
                root.month = root.today.getMonth();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.xs

        ExButton {
            kind: "flat"
            implicitWidth: titleLabel.implicitWidth + 2 * ExLooks.spacing.s
            onClicked: root.backToToday()

            // Left-aligned rather than centred like other buttons.
            contentItem: Item {
                ExText {
                    id: titleLabel
                    anchors.verticalCenter: parent.verticalCenter
                    x: ExLooks.spacing.s
                    text: root.title
                    role: "label"
                }
            }
        }
        Item {
            Layout.fillWidth: true
        }
        ExButton {
            kind: "flat"
            glyph: "keyboard_arrow_up"
            onClicked: root.turn(-1)
        }
        ExButton {
            kind: "flat"
            glyph: "keyboard_arrow_down"
            onClicked: root.turn(1)
        }
    }

    Row {
        Layout.alignment: Qt.AlignHCenter
        spacing: 2

        Repeater {
            model: 7

            ExText {
                required property int index
                width: 48
                height: 28
                horizontalAlignment: Text.AlignHCenter
                text: root.locale.dayName((root.firstDay + index) % 7, Locale.ShortFormat)
                role: "caption"
                dim: true
            }
        }
    }

    // Only the days move, under the weekday names that stay.
    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: monthGrid.implicitWidth
        implicitHeight: monthGrid.implicitHeight
        clip: true

        Grid {
            id: monthGrid

            columns: 7
            rowSpacing: 2
            columnSpacing: 2

            Repeater {
                model: root.days

                Item {
                    id: cell

                    required property var modelData
                    readonly property bool inMonth: cell.modelData.getMonth() === root.month
                    readonly property bool isToday: cell.modelData.toDateString() === root.today.toDateString()

                    width: 48
                    height: 36

                    Rectangle {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        radius: 16
                        color: cell.isToday ? ExLooks.colors.accent : "transparent"
                    }
                    ExText {
                        anchors.centerIn: parent
                        text: cell.modelData.getDate()
                        role: cell.isToday ? "label" : "body"
                        color: cell.isToday ? ExLooks.colors.accentInk : (cell.inMonth ? ExLooks.colors.text : ExLooks.colors.textDim)
                        opacity: cell.inMonth || cell.isToday ? 1 : 0.6
                    }
                }
            }
        }
    }
}
