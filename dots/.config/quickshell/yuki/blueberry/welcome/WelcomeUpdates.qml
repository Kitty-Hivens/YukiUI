import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// Whether the machine asks for updates by itself. Asked here rather than left
// switched on in silence: both checks go over the network, to the mirrors and
// to YukiUI's repository, and that is the person's call to make.
WelcomeStep {
    id: root

    title: Translation.tr("Staying up to date")
    subtitle: Translation.tr("YukiUI and the system can look for updates by themselves and say when there are some. Nothing is installed until you press Update in Settings.")

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Look for updates by themselves")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "inventory_2"
            text: Translation.tr("System packages")
            description: Translation.tr("Fetches the package lists from the mirrors")

            ExSwitch {
                checked: Config.options.updates.enableCheck
                onToggled: Config.options.updates.enableCheck = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "deployed_code"
            text: "YukiUI"
            description: Updates.shellAvailable ? Translation.tr("Asks the repository's remote for new commits")
                : Translation.tr("Not known where YukiUI was installed from")
            enabled: Updates.shellAvailable

            ExSwitch {
                checked: Config.options.updates.checkShell && Updates.shellAvailable
                onToggled: Config.options.updates.checkShell = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "terminal"
            text: Translation.tr("From a terminal")
            description: Translation.tr("./setup update in YukiUI's folder does the same as the Update button")
        }
    }
}
