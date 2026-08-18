pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import qs.waffle.widgets

WWidgetCard {
    id: root

    cardId: "weather"
    title: Weather.data.city || Translation.tr("Weather")
    // The same glyph the picker offers this card under, rather than the condition --
    // the condition is read from the icon beside the temperature.
    iconName: "weather-sunny"
    readout: Weather.data.lastRefresh ? String(Weather.data.lastRefresh).split(" • ")[0] : "--:--"

    // A block of colour, the way this card reads on the board it copies.
    color: Looks.colors.accent
    foregroundColor: Looks.colors.accentFg

    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            FluentIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: WIcons.weatherIconForCode(Weather.data.wCode)
                implicitSize: 40
                monochrome: true
                color: root.foregroundColor
            }

            WText {
                Layout.alignment: Qt.AlignVCenter
                text: Weather.data.temp || "--"
                color: root.foregroundColor
                font.pixelSize: 34
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
            color: ColorUtils.transparentize(root.foregroundColor, 0.2)
        }

        WText {
            Layout.fillWidth: true
            text: Translation.tr("Humidity %1 | Wind %2").arg(Weather.data.humidity).arg(Weather.data.wind)
            color: ColorUtils.transparentize(root.foregroundColor, 0.2)
            elide: Text.ElideRight
        }
    }
}
