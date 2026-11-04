pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry.looks

// The layouts and what the keys do. Compositor settings, applied at once and
// written into hypr/custom/general.lua by HyprInput.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var switchOptions: [
        { text: Translation.tr("Not bound"), value: "" },
        { text: "Alt + Shift", value: "grp:alt_shift_toggle" },
        { text: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" },
        { text: "Super + Space", value: "grp:win_space_toggle" },
        { text: "Caps Lock", value: "grp:caps_toggle" },
        { text: "Alt + Space", value: "grp:alt_space_toggle" },
        { text: Translation.tr("Both Shift keys"), value: "grp:shifts_toggle" }
    ]
    readonly property var capsOptions: [
        { text: Translation.tr("Caps Lock"), value: "" },
        { text: Translation.tr("Nothing"), value: "caps:none" },
        { text: "Escape", value: "caps:escape" },
        { text: "Ctrl", value: "caps:ctrl_modifier" },
        { text: "Backspace", value: "caps:backspace" },
        { text: "Super", value: "caps:super" }
    ]
    readonly property var addable: HyprInput.availableLayouts.filter(layout => !HyprInput.layouts.includes(layout.code))

    Component.onCompleted: HyprInput.refresh()

    spacing: ExLooks.settings.groupGap

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Layouts")

        // The order is the one the compositor cycles in, and the first is the
        // one a session starts on.
        Repeater {
            model: HyprInput.layouts

            SettingsCard {
                id: layout

                required property string modelData
                required property int index

                Layout.fillWidth: true
                glyph: "keyboard"
                text: HyprInput.layoutName(layout.modelData)
                description: layout.index === 0 ? `${layout.modelData}  ·  ${Translation.tr("starts here")}` : layout.modelData

                ExButton {
                    kind: "flat"
                    glyph: "arrow_upward"
                    enabled: layout.index > 0 && !HyprInput.busy
                    onClicked: HyprInput.moveLayout(layout.index, -1)
                }
                ExButton {
                    kind: "flat"
                    glyph: "close"
                    enabled: HyprInput.layouts.length > 1 && !HyprInput.busy
                    onClicked: HyprInput.removeLayout(layout.index)
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "add"
            text: Translation.tr("Add a layout")

            SettingsDropdown {
                id: addPicker
                model: root.addable.map(layout => layout.name)
                currentIndex: 0
                onActivated: index => addPicker.currentIndex = index
            }
            ExButton {
                kind: "tonal"
                text: Translation.tr("Add")
                enabled: root.addable.length > 0 && !HyprInput.busy
                onClicked: {
                    const chosen = root.addable[addPicker.currentIndex];
                    if (chosen)
                        HyprInput.addLayout(chosen.code);
                    // The one added leaves the list, and the place it held
                    // would name another layout, or none past the end.
                    addPicker.currentIndex = 0;
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Keys")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "swap_horiz"
            text: Translation.tr("Switch layout with")

            SettingsDropdown {
                // An option set outside the page and not on the list is shown
                // as it is, so another can be picked over it. Shown as the
                // first entry, picking that entry changed nothing.
                readonly property string set: HyprInput.optionEntry("grp:")
                readonly property var options: root.switchOptions.some(option => option.value === set) ? root.switchOptions
                    : [...root.switchOptions, { value: set, text: set }]
                model: options.map(option => option.text)
                currentIndex: Math.max(0, options.findIndex(option => option.value === set))
                onActivated: index => HyprInput.set(["input"], "kb_options", HyprInput.optionsWith("grp:", options[index].value))
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "keyboard_capslock"
            text: Translation.tr("Caps Lock does")

            SettingsDropdown {
                // As above, for a Caps Lock option the list does not hold.
                readonly property string set: HyprInput.optionEntry("caps:")
                readonly property var options: root.capsOptions.some(option => option.value === set) ? root.capsOptions
                    : [...root.capsOptions, { value: set, text: set }]
                model: options.map(option => option.text)
                currentIndex: Math.max(0, options.findIndex(option => option.value === set))
                onActivated: index => HyprInput.set(["input"], "kb_options", HyprInput.optionsWith("caps:", options[index].value))
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "keyboard_double_arrow_right"
            text: Translation.tr("Repeat rate")
            description: Translation.tr("How often a held key repeats")

            SettingsNumber {
                from: 1
                to: 100
                unit: Translation.tr("/s")
                value: HyprInput.repeatRate
                onEdited: value => HyprInput.set(["input"], "repeat_rate", value)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "timer"
            text: Translation.tr("Repeat starts after")

            SettingsNumber {
                from: 100
                to: 2000
                stepSize: 50
                unit: Translation.tr("ms")
                value: HyprInput.repeatDelay
                onEdited: value => HyprInput.set(["input"], "repeat_delay", value)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "pin"
            text: Translation.tr("Num Lock on at start")

            ExSwitch {
                checked: HyprInput.numlock
                onToggled: HyprInput.set(["input"], "numlock_by_default", checked)
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        Layout.topMargin: ExLooks.spacing.m
        visible: HyprInput.ready && !HyprInput.writable
        glyph: "error"
        text: Translation.tr("Applied, but not written")
        description: Translation.tr("custom/general.lua holds this setting in a shape that cannot be edited a line at a time, so it comes back on the next reload.")
    }
}
