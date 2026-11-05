pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// Which backend answers each portal request, and how to change it, as Blueberry's
// settings draw it. What it shows is PortalsModel's.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    PortalsModel {
        id: portals
    }

    spacing: ExLooks.settings.groupGap

    /** One interface: what serves it, picked from a list. */
    component InterfaceRow: SettingsCard {
        id: row

        required property var modelData
        readonly property var missing: portals.missingFor(row.modelData)
        readonly property var options: [
            { text: Translation.tr("Default"), value: "" },
            ...row.modelData.providers.map(name => ({ text: name, value: name })),
            { text: Translation.tr("Off"), value: "none" }
        ]

        Layout.fillWidth: true
        text: row.modelData.interface
        description: row.missing.length > 0 ? Translation.tr("not installed: %1").arg(row.missing.join(", "))
            : !row.modelData.explicit && row.modelData.backend.length > 0 ? row.modelData.backend
            : ""

        SettingsDropdown {
            model: row.options.map(option => option.text)
            currentIndex: Math.max(0, row.options.findIndex(option => option.value === portals.currentValue(row.modelData)))
            onActivated: index => portals.setPreference(row.modelData.interface, row.options[index].value)
        }
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "description"
            text: Translation.tr("Configuration in force")
            description: portals.lastError.length > 0 ? portals.lastError : portals.activeConfig
        }
        // The commonest way this goes wrong is editing a file that is never read:
        // a packaged kde-portals.conf looks authoritative and applies only under KDE.
        SettingsCard {
            Layout.fillWidth: true
            visible: portals.shadowed.length > 0
            glyph: "visibility_off"
            text: Translation.tr("Present but not read here")
            description: portals.shadowed.map(entry => entry.path).join(", ")
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: portals.restartNeeded
            glyph: "restart_alt"
            text: Translation.tr("Written, not in force yet")
            description: Translation.tr("Restarting cancels whatever a portal is in the middle of")

            ExButton {
                kind: "accent"
                text: Translation.tr("Restart")
                onClicked: portals.restart()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Nothing selected")
        visible: portals.unserved.length > 0

        Repeater {
            model: portals.unserved
            InterfaceRow {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Set here")
        visible: portals.ruled.length > 0

        Repeater {
            model: portals.ruled
            InterfaceRow {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: portals.defaultChain.length > 0
            ? Translation.tr("Following the default: %1").arg(portals.defaultChain.join(" → "))
            : Translation.tr("Following the default")
        visible: portals.followed.length > 0

        Repeater {
            model: portals.followed
            InterfaceRow {}
        }
    }
}
