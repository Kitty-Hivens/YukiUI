import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// The last step: done, where the rest is, and whether this comes back.
WelcomeStep {
    id: root

    /**
     * Whether the welcome opens at the next start. The shell opens it when the
     * file that says the greeting is done is missing, so this removes it or
     * writes it back. Not through the shell's own first-run service: brought up
     * in this process, it would find the file missing and greet again.
     */
    readonly property string firstRunFile: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property bool again: false

    function setAgain(wanted: bool) {
        root.again = wanted;
        if (wanted)
            Quickshell.execDetached(["rm", "-f", root.firstRunFile]);
        else
            Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "This file is just here to confirm you\'ve been greeted :>" > "$1"', "welcome", root.firstRunFile]);
    }

    title: Translation.tr("All set")
    subtitle: Translation.tr("Enjoy it. Everything chosen here, and a lot more, is in Settings.")

    // The desktop as it now stands, every choice above in one picture.
    WelcomeDesktop {
        Layout.preferredWidth: 400
        Layout.preferredHeight: Math.round(400 * 9 / 16)
        Layout.alignment: Qt.AlignHCenter
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "settings"
            text: Translation.tr("Open Settings")
            description: Translation.tr("Super+I opens them any time")
            leads: true
            onClicked: Quickshell.execDetached(["bash", "-c", "\"$HOME/.config/hypr/hyprland/scripts/launch_settings.sh\""])
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "waving_hand"
            text: Translation.tr("Show this at the next start")
            description: Translation.tr("Super+Shift+Alt+/ opens it any time")

            ExSwitch {
                checked: root.again
                onToggled: root.setAgain(checked)
            }
        }
    }
}
