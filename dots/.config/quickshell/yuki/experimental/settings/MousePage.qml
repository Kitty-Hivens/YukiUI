import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks

// The pointer and the touchpad. Compositor settings, applied at once and
// written into hypr/custom/general.lua by HyprInput.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    Component.onCompleted: HyprInput.refresh()

    spacing: ExLooks.spacing.s

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Mouse")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "speed"
            text: Translation.tr("Pointer speed")

            ExSlider {
                implicitWidth: 240
                from: -1
                to: 1
                stepSize: 0.05
                value: HyprInput.mouseSensitivity
                // Written once the knob is let go, not on every step of a drag.
                onPressedChanged: {
                    if (!pressed)
                        HyprInput.set(["input"], "sensitivity", Math.round(value * 100) / 100);
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "trending_up"
            text: Translation.tr("Speed up with a faster hand")
            description: Translation.tr("Off, the pointer moves as far as the hand, however fast")

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
}
