import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// The first step: what this is, the desktop as it stands, and the language,
// which comes first because everything after it is read in it.
WelcomeStep {
    id: root

    readonly property var languages: ["auto", ...Translation.allAvailableLanguages]

    function languageName(code: string): string {
        if (code === "auto")
            return Translation.tr("Auto (System)");
        const native = Qt.locale(code).nativeLanguageName;
        return native.length > 0 ? `${native.charAt(0).toUpperCase()}${native.slice(1)}  ·  ${code}` : code;
    }

    title: Translation.tr("Welcome to YukiUI")
    subtitle: Translation.tr("This is Blueberry: windows that stay where you put them, and a dock that holds what is open. A few things to set up first. Every one of them can be changed later in Settings.")

    WelcomeDesktop {
        Layout.fillWidth: true
        Layout.maximumWidth: 600
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: Math.round(width * 9 / 16)
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "language"
            text: Translation.tr("Language")

            SettingsDropdown {
                model: root.languages.map(code => root.languageName(code))
                currentIndex: Math.max(0, root.languages.indexOf(Config.options.language.ui))
                onActivated: index => Config.options.language.ui = root.languages[index]
            }
        }
    }
}
