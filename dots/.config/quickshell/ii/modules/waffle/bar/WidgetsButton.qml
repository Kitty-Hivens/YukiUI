import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import qs
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

AppButton {
    id: root

    // The button this copies is a weather reading: a condition icon and the
    // temperature, widening to carry them where the taskbar is left-aligned.
    readonly property bool expandedForm: Config.options.waffles.bar.leftAlignApps
    readonly property string temperature: Weather.data.temp || ""
    leftInset: Config.options.waffles.bar.leftAlignApps ? 0 : 12
    implicitWidth: expandedForm ? 148 : (contentItem.implicitWidth + 24 + leftInset + rightInset)
    iconName: WIcons.weatherIconForCode(Weather.data.wCode)

    checked: GlobalStates.widgetsOpen
    onClicked: {
        GlobalStates.widgetsOpen = !GlobalStates.widgetsOpen;
    }
    onDownChanged: {
        scaleAnim.duration = root.down ? 150 : 200;
        scaleAnim.easing.bezierCurve = root.down ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut;
        iconWidget.scale = root.down ? 5 / 6 : 1; // If/When we do dragging, the scale is 1.25
    }

    contentItem: Item {
        anchors {
            verticalCenter: parent.verticalCenter
            left: root.expandedForm ? parent.left : undefined
            horizontalCenter: root.expandedForm ? undefined : background.horizontalCenter
        }
        implicitHeight: row.implicitHeight
        implicitWidth: row.implicitWidth
        Row {
            id: row
            anchors {
                verticalCenter: parent.verticalCenter
                left: root.expandedForm ? parent.left : undefined
                horizontalCenter: root.expandedForm ? undefined : parent.horizontalCenter
                margins: 8
            }
            spacing: 6

            FluentIcon {
                id: iconWidget
                anchors.verticalCenter: parent.verticalCenter
                icon: root.iconName
                implicitSize: 20

                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        easing.type: Easing.BezierSpline
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                WText {
                    visible: root.temperature.length > 0
                    text: root.temperature
                    font.pixelSize: Looks.font.pixelSize.large
                }
                WText {
                    visible: root.expandedForm
                    text: Weather.data.city || Translation.tr("Widgets")
                    color: Looks.colors.subfg
                }
            }
        }
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip
        text: root.temperature.length > 0 ? Translation.tr("%1 in %2").arg(root.temperature).arg(Weather.data.city) : Translation.tr("Widgets")
    }
}
