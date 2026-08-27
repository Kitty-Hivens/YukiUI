pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common

/**
 * One installed plugin: what it is, whether it runs, and the settings it
 * declared in its manifest.
 *
 * The controls are built from the declared defaults rather than from a schema
 * with types in it, because the defaults are what a plugin actually ships: a
 * boolean default means a switch, a number means a number, and anything else
 * means a line of text. A plugin that needs richer controls than that gets them
 * when it needs them, not before.
 */
ColumnLayout {
    id: root
    required property var entry

    readonly property bool off: Plugins.isDisabled(root.entry.id)
    readonly property string problem: root.entry.problem ?? ""
    readonly property var schema: root.entry.schema
    readonly property var settings: root.entry.settings
    readonly property list<string> keys: root.schema ? Object.keys(root.schema) : []
    // Keys whose default is a list or an object. They are stored and handed to
    // the plugin like any other, but there is no honest control for them here.
    readonly property list<string> deepKeys: root.keys.filter(key => {
        const value = root.schema[key];
        return value !== null && typeof value === "object";
    })

    /** "alsoStop" -> "Also stop". The manifest carries no labels to use instead. */
    function humanise(key) {
        const spaced = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ");
        return spaced.charAt(0).toUpperCase() + spaced.slice(1);
    }

    function put(key, value) {
        if (root.settings)
            root.settings[key] = value;
    }

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        MaterialSymbol {
            text: root.problem.length > 0 ? "extension_off" : "extension"
            iconSize: Appearance.font.pixelSize.hugeass
            color: root.problem.length > 0 ? Appearance.colors.colError
                : root.entry.running ? Appearance.colors.colPrimary
                : Appearance.colors.colSubtext
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.entry.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                // The directory as well as the id: two directories can declare the
                // same id, and then only one of them is the plugin that is running.
                text: root.entry.id.length > 0 ? `${root.entry.id} · ${root.entry.directory}` : root.entry.directory
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            // On and off, not running: only the process that hosts plugins knows
            // the second, and this window is not that process. The switch is a
            // decision the running shell picks up, not a report from it.
            text: root.problem.length > 0 ? Translation.tr("Not built")
                : root.off ? Translation.tr("Off")
                : Translation.tr("On")
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.problem.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
        }

        StyledSwitch {
            id: enableSwitch
            // A plugin refused for a broken manifest cannot be switched on, and
            // saying so with a dead control beats letting someone flip it and
            // watch nothing happen.
            enabled: root.problem.length === 0 && root.entry.id.length > 0
            // Restated through Binding: the control writes its own property when
            // touched, which drops the binding and leaves it showing what was
            // asked for rather than what the registry did.
            Binding {
                target: enableSwitch
                property: "checked"
                value: !root.off
                restoreMode: Binding.RestoreBindingOrValue
            }
            onCheckedChanged: {
                if (checked === !root.off)
                    return;
                Plugins.setDisabled(root.entry.id, !checked);
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.problem.length > 0
        text: root.problem
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colError
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 10
        visible: root.keys.length > 0
        spacing: 6

        Repeater {
            model: root.keys.filter(key => root.deepKeys.indexOf(key) === -1)

            delegate: Loader {
                id: controlLoader
                required property string modelData
                readonly property var fallback: root.schema[modelData]
                readonly property var current: root.settings ? root.settings[modelData] : controlLoader.fallback
                Layout.fillWidth: true
                sourceComponent: typeof controlLoader.fallback === "boolean" ? boolControl
                    : typeof controlLoader.fallback === "number" ? numberControl
                    : textControl

                Component {
                    id: boolControl
                    ConfigSwitch {
                        id: pluginSwitch
                        text: root.humanise(controlLoader.modelData)
                        Binding {
                            target: pluginSwitch
                            property: "checked"
                            value: controlLoader.current === true
                            restoreMode: Binding.RestoreBindingOrValue
                        }
                        onCheckedChanged: {
                            if (checked !== (controlLoader.current === true))
                                root.put(controlLoader.modelData, checked);
                        }
                    }
                }

                Component {
                    id: numberControl
                    ConfigSpinBox {
                        id: pluginSpin
                        text: root.humanise(controlLoader.modelData)
                        from: -1000000
                        to: 1000000
                        stepSize: 1
                        Binding {
                            target: pluginSpin
                            property: "value"
                            value: controlLoader.current ?? 0
                            restoreMode: Binding.RestoreBindingOrValue
                        }
                        onValueChanged: {
                            if (value !== controlLoader.current)
                                root.put(controlLoader.modelData, value);
                        }
                    }
                }

                Component {
                    id: textControl
                    // The same shape every other text setting in the shell has: a
                    // titled subsection over a text area. No placeholder: the
                    // manifest default is usually the value as well, and the two
                    // then stack on top of each other.
                    ContentSubsection {
                        title: root.humanise(controlLoader.modelData)

                        MaterialTextArea {
                            Layout.fillWidth: true
                            text: controlLoader.current ?? ""
                            wrapMode: TextEdit.NoWrap
                            onTextChanged: {
                                if (text !== controlLoader.current)
                                    root.put(controlLoader.modelData, text);
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.deepKeys.length > 0
            text: Translation.tr("Kept in the plugin's own file: %1").arg(root.deepKeys.join(", "))
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: root.keys.length === 0 && root.problem.length === 0
        text: Translation.tr("Nothing to configure")
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colSubtext
    }
}
