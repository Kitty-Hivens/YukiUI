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

    cardId: "weather"
    title: Weather.data.city || Translation.tr("Weather")
    iconName: WIcons.weatherIconForCode(Weather.data.wCode)

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            FluentIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: WIcons.weatherIconForCode(Weather.data.wCode)
                implicitSize: 44
            }

            WText {
                Layout.alignment: Qt.AlignVCenter
                text: Weather.data.temp || "--"
                font.pixelSize: 32
                font.weight: Looks.font.weight.thin
            }

            Item {
                Layout.fillWidth: true
            }
        }

        WText {
            Layout.fillWidth: true
            visible: (Weather.data.tempFeelsLike ?? "").length > 0
            text: Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike)
            color: Looks.colors.subfg
        }

        WText {
            Layout.fillWidth: true
            text: Translation.tr("Humidity %1 | Wind %2").arg(Weather.data.humidity).arg(Weather.data.wind)
            color: Looks.colors.subfg
            elide: Text.ElideRight
        }
    }
}
