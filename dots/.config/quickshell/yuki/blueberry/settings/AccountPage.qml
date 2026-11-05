pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// Who is signed in, and how the machine lets them back in. The password is changed
// in a terminal, where passwd can put its own questions: they depend on how PAM is
// set up here, and a form guessing at them would be wrong on some machine.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var account: root.settings?.account ?? null
    readonly property string username: root.settings?.username ?? SystemInfo.username
    readonly property string shownName: (root.account?.realName ?? "").length > 0 ? root.account.realName : root.username
    readonly property var metrics: ExLooks.settings

    spacing: root.metrics.groupGap

    FileDialog {
        id: picker
        title: Translation.tr("Choose a picture")
        nameFilters: [`${Translation.tr("Pictures")} (*.png *.jpg *.jpeg *.webp *.avif *.bmp)`]
        onAccepted: root.account?.setPicture(FileUtils.trimFileProtocol(picker.selectedFile.toString()))
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: profile.implicitHeight + 2 * root.metrics.rowPadding
        radius: root.metrics.plateRadius
        color: root.metrics.plate

        RowLayout {
            id: profile

            anchors.fill: parent
            anchors.margins: root.metrics.rowPadding
            spacing: root.metrics.rowPadding

            ExAvatar {
                size: 72
                name: root.username
                revision: root.account?.pictureRevision ?? 0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ExText {
                    Layout.fillWidth: true
                    text: root.shownName
                    font.pixelSize: root.metrics.heading
                    font.weight: ExLooks.font.weightTitle
                    elide: Text.ElideRight
                }
                ExText {
                    Layout.fillWidth: true
                    text: root.account?.administrator ? Translation.tr("Local account  ·  Administrator") : Translation.tr("Local account")
                    font.pixelSize: root.metrics.small
                    dim: true
                }
                ExText {
                    Layout.fillWidth: true
                    visible: (root.account?.failure ?? "").length > 0
                    text: root.account?.failure ?? ""
                    font.pixelSize: root.metrics.small
                    color: ExLooks.colors.destructive
                    wrapMode: Text.Wrap
                }
            }
            ExButton {
                kind: "control"
                enabled: !(root.account?.busy ?? false)
                text: Translation.tr("Change picture")
                onClicked: picker.open()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Profile")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "badge"
            text: Translation.tr("Full name")

            ExTextField {
                id: nameField
                width: 220
                text: root.account?.realName ?? ""
                placeholder: root.username
            }
            ExButton {
                visible: nameField.text !== (root.account?.realName ?? "")
                kind: "accent"
                enabled: !(root.account?.busy ?? false)
                text: Translation.tr("Save")
                onClicked: root.account.setRealName(nameField.text)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "person"
            text: Translation.tr("Username")

            ExText {
                text: root.username
                dim: true
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Signing in")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "password"
            text: Translation.tr("Password")
            description: Translation.tr("Changed in a terminal")

            ExButton {
                kind: "control"
                text: Translation.tr("Change")
                onClicked: Session.changePassword()
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "lock"
            text: Translation.tr("Lock the screen when the session starts")

            ExSwitch {
                checked: Config.options.lock.launchOnStartup
                onToggled: Config.options.lock.launchOnStartup = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "key"
            text: Translation.tr("Open saved passwords together with the screen")

            ExSwitch {
                checked: Config.options.lock.security.unlockKeyring
                onToggled: Config.options.lock.security.unlockKeyring = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "timer"
            text: Translation.tr("When the screen locks by itself")
            leads: true
            onClicked: root.settings.open("power")
        }
    }
}
