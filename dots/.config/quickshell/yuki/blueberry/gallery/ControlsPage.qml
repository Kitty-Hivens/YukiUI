import QtQuick
import QtQuick.Layouts
import qs.blueberry.looks

// Every control in every state it has, drawn at rest so a screenshot can show
// hover and press.
Item {
    implicitWidth: 1000
    implicitHeight: 720

    RowLayout {
        anchors.fill: parent
        anchors.margins: ExLooks.spacing.xl
        spacing: ExLooks.spacing.xl

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 440
            Layout.maximumWidth: 440
            spacing: ExLooks.spacing.m

            ExText {
                text: "blueberry"
                role: "title"
            }

            GalleryCaption { text: "Кнопки" }
            RowLayout {
                spacing: ExLooks.spacing.s
                ExButton { kind: "accent"; text: "Готово" }
                ExButton { kind: "tonal"; text: "Открыть" }
                ExButton { kind: "control"; text: "Отмена" }
                ExButton { kind: "flat"; text: "Ещё" }
            }

            GalleryCaption { text: "Состояния: покой, наведение, нажатие, выключена" }
            RowLayout {
                spacing: ExLooks.spacing.s
                ExButton { kind: "control"; text: "Кнопка" }
                ExButton { kind: "control"; text: "Кнопка"; previewState: "hover" }
                ExButton { kind: "control"; text: "Кнопка"; previewState: "pressed" }
                ExButton { kind: "control"; text: "Кнопка"; enabled: false }
            }
            RowLayout {
                spacing: ExLooks.spacing.s
                ExButton { kind: "accent"; text: "Готово" }
                ExButton { kind: "accent"; text: "Готово"; previewState: "hover" }
                ExButton { kind: "accent"; text: "Готово"; previewState: "pressed" }
                ExButton { kind: "accent"; text: "Готово"; enabled: false }
            }

            GalleryCaption { text: "Кнопки-глифы" }
            RowLayout {
                spacing: ExLooks.spacing.s
                ExButton { kind: "control"; glyph: "settings" }
                ExButton { kind: "control"; glyph: "power_settings_new"; previewState: "hover" }
                ExButton { kind: "tonal"; glyph: "edit" }
                ExButton { kind: "flat"; glyph: "more_horiz" }
                ExButton { kind: "control"; glyph: "search"; text: "Поиск" }
            }

            GalleryCaption { text: "Переключатели: выкл, вкл, нажатие, выключен" }
            RowLayout {
                spacing: ExLooks.spacing.l
                ExSwitch {}
                ExSwitch { checked: true }
                ExSwitch { previewState: "pressed" }
                ExSwitch { checked: true; previewState: "pressed" }
                ExSwitch { enabled: false }
                ExSwitch { enabled: false; checked: true }
            }

            GalleryCaption { text: "Слайдеры" }
            ExSlider { Layout.fillWidth: true; value: 0.3 }
            ExSlider { Layout.fillWidth: true; value: 0.75 }
            ExSlider { Layout.fillWidth: true; value: 0.5; enabled: false }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.minimumWidth: 440
            spacing: ExLooks.spacing.m

            GalleryCaption { text: "Быстрые настройки" }
            ExSurface {
                Layout.fillWidth: true
                implicitHeight: quickSettings.implicitHeight + 2 * ExLooks.spacing.l

                QuickSettingsMock {
                    id: quickSettings
                    anchors.fill: parent
                    anchors.margins: ExLooks.spacing.l
                }
            }

            GalleryCaption { text: "Контекстное меню приложения в доке" }
            ExMenu {
                ExMenuItem { glyph: "open_in_new"; text: "Новое окно"; shortcut: "Ctrl+N" }
                ExMenuItem { glyph: "keep"; text: "Закрепить в доке"; previewState: "hover" }
                ExMenuSeparator {}
                ExMenuItem { glyph: "minimize"; text: "Свернуть" }
                ExMenuItem { glyph: "move_group"; text: "На рабочий стол"; hasSubmenu: true }
                ExMenuItem { glyph: "lock"; text: "Недоступно"; enabled: false }
                ExMenuSeparator {}
                ExMenuItem { glyph: "close"; text: "Закрыть окно"; destructive: true }
            }
        }
    }
}
