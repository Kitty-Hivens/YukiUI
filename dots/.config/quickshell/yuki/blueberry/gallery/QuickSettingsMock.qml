import QtQuick
import QtQuick.Layouts
import qs.blueberry.looks

ColumnLayout {
    width: 440
    spacing: ExLooks.spacing.s

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: ExLooks.spacing.s
        rowSpacing: ExLooks.spacing.s

        ExToggleTile { Layout.fillWidth: true; glyph: "wifi"; text: "Wi-Fi"; subtitle: "Домашняя"; checked: true; hasMenu: true }
        ExToggleTile { Layout.fillWidth: true; glyph: "bluetooth"; text: "Bluetooth"; subtitle: "Выключен"; hasMenu: true }
        ExToggleTile { Layout.fillWidth: true; glyph: "bolt"; text: "Режим питания"; subtitle: "Баланс"; hasMenu: true }
        ExToggleTile { Layout.fillWidth: true; glyph: "nightlight"; text: "Ночной свет"; checked: true }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: ExLooks.spacing.s
        spacing: ExLooks.spacing.m
        ExGlyph { text: "volume_up" }
        ExSlider { Layout.fillWidth: true; value: 0.62 }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.m
        ExGlyph { text: "brightness_6" }
        ExSlider { Layout.fillWidth: true; value: 0.4 }
    }
}
