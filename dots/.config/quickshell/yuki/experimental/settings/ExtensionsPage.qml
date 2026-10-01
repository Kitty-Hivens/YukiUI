pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.experimental.looks

// The shell's plugins: which are installed, which are on, why one would not
// build, and the settings each declared in its manifest. This window reads the
// manifests and builds none of them, so switching one here is a decision the
// running shell picks up.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var entries: Plugins.entries
    readonly property int onCount: root.entries.filter(entry => !Plugins.isDisabled(entry.id)).length

    /** "alsoStop" -> "Also stop". The manifest carries no labels to use instead. */
    function humanise(key: string): string {
        const spaced = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ");
        return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
    }

    spacing: ExLooks.spacing.s

    // One plugin, opening onto what it lets be set.
    component PluginBlock: SettingsExpander {
        id: plugin

        required property var modelData
        readonly property bool off: Plugins.isDisabled(plugin.modelData.id)
        readonly property string problem: plugin.modelData.problem ?? ""
        readonly property var schema: plugin.modelData.schema
        // A default that is a list or an object has no honest control here. It
        // is still kept and handed to the plugin, from the plugin's own file.
        readonly property var keys: plugin.schema ? Object.keys(plugin.schema).filter(key => plugin.schema[key] === null || typeof plugin.schema[key] !== "object") : []
        readonly property var deepKeys: plugin.schema ? Object.keys(plugin.schema).filter(key => plugin.keys.indexOf(key) === -1) : []

        function put(key: string, value) {
            if (plugin.modelData.settings)
                plugin.modelData.settings[key] = value;
        }

        Layout.fillWidth: true
        glyph: plugin.problem.length > 0 ? "extension_off" : "extension"
        text: plugin.modelData.name
        description: plugin.problem.length > 0 ? plugin.problem
            : plugin.modelData.id.length > 0 ? `${plugin.modelData.id}  ·  ${plugin.modelData.directory}`
            : plugin.modelData.directory

        // One that would not build cannot be switched on, and a dead switch
        // says so better than one that flips and changes nothing.
        control: ExSwitch {
            enabled: plugin.problem.length === 0 && plugin.modelData.id.length > 0
            checked: !plugin.off && plugin.problem.length === 0
            onToggled: Plugins.setDisabled(plugin.modelData.id, !checked)
        }

        Repeater {
            model: plugin.keys

            SettingsCard {
                id: option

                required property string modelData
                readonly property var fallback: plugin.schema[option.modelData]
                readonly property var current: plugin.modelData.settings ? plugin.modelData.settings[option.modelData] : option.fallback

                Layout.fillWidth: true
                flat: true
                text: Translation.tr(root.humanise(option.modelData))

                ExSwitch {
                    visible: typeof option.fallback === "boolean"
                    checked: option.current === true
                    onToggled: plugin.put(option.modelData, checked)
                }
                SettingsNumber {
                    visible: typeof option.fallback === "number"
                    from: -1000000
                    to: 1000000
                    value: typeof option.current === "number" ? option.current : 0
                    onEdited: value => plugin.put(option.modelData, value)
                }
                ExTextField {
                    id: field
                    visible: typeof option.fallback !== "boolean" && typeof option.fallback !== "number"
                    width: 260
                    text: typeof option.current === "string" ? option.current : ""

                    Connections {
                        target: field.input
                        function onEditingFinished() {
                            if (field.text !== option.current)
                                plugin.put(option.modelData, field.text);
                        }
                    }
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: plugin.deepKeys.length > 0
            flat: true
            text: Translation.tr("Kept in the plugin's own file: %1").arg(plugin.deepKeys.join(", "))
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: plugin.keys.length === 0 && plugin.deepKeys.length === 0
            flat: true
            text: Translation.tr("Nothing to configure")
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        glyph: "extension"
        text: root.entries.length > 0 ? Translation.tr("%1 of %2 on").arg(root.onCount).arg(root.entries.length) : Translation.tr("No plugins installed")
        description: root.entries.length > 0 ? Translation.tr("A plugin switched off is never built, so it cannot start a process or claim a shortcut while it is off")
            : Translation.tr("Drop a directory with a manifest into the plugins folder and it appears here")

        ExButton {
            kind: "control"
            glyph: "folder_open"
            text: Translation.tr("Open the folder")
            onClicked: Qt.openUrlExternally(`file://${Plugins.homeRoot}`)
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Installed")
        visible: root.entries.length > 0

        Repeater {
            model: root.entries
            PluginBlock {}
        }
    }
}
