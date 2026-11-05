import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.blueberry.looks

// The pointer and the touchpad. Compositor settings, applied at once and
// written into hypr/custom/general.lua by HyprInput.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    Component.onCompleted: HyprInput.refresh()

    readonly property var gestureModes: [
        { value: "workspaces", text: Translation.tr("Switch workspaces and show the desktop") },
        { value: "move", text: Translation.tr("Move windows") },
        { value: "none", text: Translation.tr("Nothing") },
        { value: "custom", text: Translation.tr("Custom") }
    ]
    readonly property var sidewaysActions: [
        { value: "none", text: Translation.tr("Nothing") },
        { value: "workspace", text: Translation.tr("Switch workspaces") }
    ]
    readonly property var swipeActions: [
        { value: "none", text: Translation.tr("Nothing") },
        { value: "search", text: Translation.tr("Search and apps") },
        { value: "showDesktop", text: Translation.tr("Show the desktop") },
        { value: "notifications", text: Translation.tr("Notifications") },
        { value: "quickSettings", text: Translation.tr("Quick settings") },
        { value: "maximize", text: Translation.tr("Maximise or restore the window") }
    ]

    function indexOfValue(list, value): int {
        return Math.max(0, list.findIndex(entry => entry.value === value));
    }

    /** What swipes with so many fingers do, as Windows offers it: a set, or each direction on its own. */
    component FingerGestures: SettingsExpander {
        id: gestures

        /** "three" or "four", where the settings keep it. */
        required property string key
        readonly property var set: Config.options.blueberry.gestures[gestures.key]
        readonly property bool custom: gestures.set.mode === "custom"

        Layout.fillWidth: true
        glyph: "swipe"
        description: gestures.set.mode === "workspaces" ? Translation.tr("Sideways between workspaces, up for search, down for the desktop")
            : gestures.set.mode === "move" ? Translation.tr("The window under the fingers moves, a pinch makes it fullscreen")
            : gestures.custom ? Translation.tr("Each direction as set below")
            : ""

        control: SettingsDropdown {
            model: root.gestureModes.map(mode => mode.text)
            currentIndex: root.indexOfValue(root.gestureModes, gestures.set.mode)
            onActivated: index => {
                gestures.set.mode = root.gestureModes[index].value;
                if (gestures.set.mode === "custom")
                    gestures.expanded = true;
            }
        }

        SettingsCard {
            Layout.fillWidth: true
            flat: true
            enabled: gestures.custom
            text: Translation.tr("Swipe sideways")

            SettingsDropdown {
                model: root.sidewaysActions.map(action => action.text)
                currentIndex: root.indexOfValue(root.sidewaysActions, gestures.set.sideways)
                onActivated: index => gestures.set.sideways = root.sidewaysActions[index].value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            flat: true
            enabled: gestures.custom
            text: Translation.tr("Swipe up")

            SettingsDropdown {
                model: root.swipeActions.map(action => action.text)
                currentIndex: root.indexOfValue(root.swipeActions, gestures.set.up)
                onActivated: index => gestures.set.up = root.swipeActions[index].value
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            flat: true
            enabled: gestures.custom
            text: Translation.tr("Swipe down")

            SettingsDropdown {
                model: root.swipeActions.map(action => action.text)
                currentIndex: root.indexOfValue(root.swipeActions, gestures.set.down)
                onActivated: index => gestures.set.down = root.swipeActions[index].value
            }
        }
    }

    spacing: ExLooks.settings.groupGap

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Mouse")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "speed"
            text: Translation.tr("Pointer speed")

            ExSlider {
                id: speedSlider
                implicitWidth: 240
                from: -1
                to: 1
                stepSize: 0.05
                value: HyprInput.mouseSensitivity
                // Felt as the knob moves, as on Windows, at most every 120 ms,
                // and once more as it is let go.
                onMoved: {
                    if (!speedWrite.running)
                        speedWrite.start();
                }
                onPressedChanged: {
                    if (!pressed) {
                        speedWrite.stop();
                        HyprInput.set(["input"], "sensitivity", Math.round(value * 100) / 100);
                    }
                }

                Timer {
                    id: speedWrite
                    interval: 120
                    onTriggered: HyprInput.set(["input"], "sensitivity", Math.round(speedSlider.value * 100) / 100)
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "trending_up"
            text: Translation.tr("Speed up with a faster hand")

            ExSwitch {
                checked: HyprInput.mouseAccelProfile !== "flat"
                onToggled: HyprInput.set(["input"], "accel_profile", checked ? "adaptive" : "flat")
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "swap_horiz"
            text: Translation.tr("Left-handed")
            description: Translation.tr("The buttons swap sides")

            ExSwitch {
                checked: HyprInput.leftHanded
                onToggled: HyprInput.set(["input"], "left_handed", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "swipe_vertical"
            text: Translation.tr("Content follows the wheel")

            ExSwitch {
                checked: HyprInput.mouseNaturalScroll
                onToggled: HyprInput.set(["input"], "natural_scroll", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "swipe_down"
            text: Translation.tr("Scroll speed")

            SettingsNumber {
                from: 10
                to: 300
                stepSize: 10
                unit: "%"
                value: Math.round(HyprInput.mouseScrollFactor * 100)
                onEdited: value => HyprInput.set(["input"], "scroll_factor", value / 100)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Touchpad")
        visible: HyprInput.touchpadDevice.length > 0

        SettingsCard {
            Layout.fillWidth: true
            glyph: "touch_app"
            text: Translation.tr("Tap to click")

            ExSwitch {
                checked: HyprInput.touchpadTapToClick
                onToggled: HyprInput.set(["input", "touchpad"], "tap_to_click", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: HyprInput.touchpadTapToClick
            glyph: "drag_pan"
            text: Translation.tr("Tap and drag")

            ExSwitch {
                checked: HyprInput.touchpadTapAndDrag
                onToggled: HyprInput.set(["input", "touchpad"], "tap_and_drag", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "swipe_vertical"
            text: Translation.tr("Content follows the fingers")

            ExSwitch {
                checked: HyprInput.touchpadNaturalScroll
                onToggled: HyprInput.set(["input", "touchpad"], "natural_scroll", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "block"
            text: Translation.tr("Ignore it while typing")

            ExSwitch {
                checked: HyprInput.touchpadDisableWhileTyping
                onToggled: HyprInput.set(["input", "touchpad"], "disable_while_typing", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "ads_click"
            text: Translation.tr("Two fingers for a right click")

            ExSwitch {
                checked: HyprInput.touchpadClickfinger
                onToggled: HyprInput.set(["input", "touchpad"], "clickfinger_behavior", checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "swipe_down"
            text: Translation.tr("Scroll speed")

            SettingsNumber {
                from: 10
                to: 300
                stepSize: 5
                unit: "%"
                value: Math.round(HyprInput.touchpadScrollFactor * 100)
                onEdited: value => HyprInput.set(["input", "touchpad"], "scroll_factor", value / 100)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Touchpad gestures")
        visible: HyprInput.touchpadDevice.length > 0

        FingerGestures {
            key: "three"
            text: Translation.tr("Three fingers")
        }
        FingerGestures {
            key: "four"
            text: Translation.tr("Four fingers")
        }
        ExText {
            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.xs
            text: Translation.tr("A change here resets game mode")
            role: "caption"
            dim: true
            wrapMode: Text.Wrap
        }
    }
}
