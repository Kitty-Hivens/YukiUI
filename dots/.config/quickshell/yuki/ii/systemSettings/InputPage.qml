pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.ii.systemSettings
import qs.common.widgets
import qs.common

/**
 * What the keyboard does and what the touchpad does.
 *
 * Everything here is a compositor setting rather than a shell one, so a change
 * takes effect at once and is written into the one config file meant to hold a
 * person's own -- see [HyprInput], which also explains why that file and not the
 * shell's own override slot.
 *
 * Deliberately not here: input methods. Anything past an xkb layout -- preedit,
 * candidates, anything that turns several keys into one character -- needs a
 * protocol the shell does not speak, and a page that offered a switch for it
 * would be offering something nothing could carry out.
 */
Item {
    id: root

    Component.onCompleted: {
        HyprInput.refresh();
        root.syncLayouts();
    }

    /**
     * Brings the shown list back in line with the compositor's, and does nothing
     * at all when they already agree.
     *
     * They agree after every change made here, because the row is moved and the
     * service is told in the same breath. What this is for is the other case: a
     * write that did not take, or the file changed by hand while the page is
     * open. That one rebuilds and does not animate, which is right -- nothing on
     * screen moved, the answer simply turned out to be different.
     */
    function syncLayouts() {
        const codes = HyprInput.layouts;
        if (layoutModel.count === codes.length) {
            let same = true;
            for (let i = 0; i < codes.length; i++) {
                if (layoutModel.get(i).code !== codes[i]) {
                    same = false;
                    break;
                }
            }
            if (same)
                return;
        }
        layoutModel.clear();
        codes.forEach(code => layoutModel.append(({ code: code })));
    }

    Connections {
        target: HyprInput
        function onLayoutsChanged() {
            root.syncLayouts();
        }
    }

    /** The device as the compositor names it, which is also what a rule for it would match. */
    function deviceName(name) {
        return name.replace(/^-+/, "").replace(/-+$/, "");
    }

    readonly property var switchOptions: [
        { displayName: Translation.tr("Not bound"), value: "" },
        { displayName: "Alt + Shift", value: "grp:alt_shift_toggle" },
        { displayName: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" },
        { displayName: "Super + Space", value: "grp:win_space_toggle" },
        { displayName: "Caps Lock", value: "grp:caps_toggle" },
        { displayName: "Alt + Space", value: "grp:alt_space_toggle" },
        { displayName: Translation.tr("Both Shift keys"), value: "grp:shifts_toggle" }
    ]

    readonly property var capsOptions: [
        { displayName: Translation.tr("Caps Lock"), value: "" },
        { displayName: Translation.tr("Nothing"), value: "caps:none" },
        { displayName: "Escape", value: "caps:escape" },
        { displayName: "Ctrl", value: "caps:ctrl_modifier" },
        { displayName: "Backspace", value: "caps:backspace" },
        { displayName: "Super", value: "caps:super" }
    ]

    /**
     * One layout in the list, with what it takes to put it somewhere else or
     * take it out. The order is the order the compositor cycles them in, and the
     * first is the one a session starts on, so it is worth being able to change.
     */
    component LayoutRow: RowLayout {
        id: layoutRow
        required property int index
        required property string code

        spacing: 10

        StyledText {
            Layout.preferredWidth: 52
            text: layoutRow.code
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: HyprInput.layoutName(layoutRow.code)
            elide: Text.ElideRight
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            visible: layoutRow.index === 0
            text: Translation.tr("starts here")
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
        RippleButton {
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            enabled: layoutRow.index > 0
            // The row moves first and the compositor is told after: the list is
            // what was clicked on, and it should not wait on a process to say so.
            onClicked: {
                layoutModel.move(layoutRow.index, layoutRow.index - 1, 1);
                HyprInput.moveLayout(layoutRow.index, -1);
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_upward"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
        }
        RippleButton {
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            enabled: HyprInput.layouts.length > 1
            onClicked: {
                const index = layoutRow.index;
                HyprInput.removeLayout(index);
                layoutModel.remove(index, 1);
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true
                icon: "keyboard"
                title: HyprInput.mainKeyboard.length > 0
                    ? root.deviceName(HyprInput.mainKeyboard)
                    : Translation.tr("No keyboard")
                subtitle: Translation.tr("The one being typed on. What is set here is set for all of them.")

                FactRow {
                    // Said plainly, because the number is startling: anything that
                    // can send a key is a keyboard to the compositor, headsets and
                    // power buttons included.
                    label: Translation.tr("Devices that send keys")
                    value: HyprInput.keyboardCount > 0 ? String(HyprInput.keyboardCount) : ""
                }
                FactRow {
                    label: Translation.tr("Touchpad")
                    value: root.deviceName(HyprInput.touchpadDevice)
                }
            }

            PageHeading {
                text: Translation.tr("Layouts")
            }

            SystemCard {
                Layout.fillWidth: true

                // A positioner over a model rather than a layout over an array:
                // a list rebuilt from a new array has no move to animate, because
                // every row was destroyed and made again where it landed. With a
                // model the row that moved is the row that moves.
                Column {
                    id: layoutColumn
                    Layout.fillWidth: true
                    spacing: 4

                    move: Transition {
                        animations: [
                            Appearance.animation.elementMove.numberAnimation.createObject(this, ({ property: "y" }))
                        ]
                    }
                    // No transition for a row appearing. A layout is added by
                    // picking it from a list and pressing a button, so where it
                    // came from is not in question, and growing it out of nothing
                    // answers a question nobody asked.

                    Repeater {
                        model: ListModel {
                            id: layoutModel
                        }

                        delegate: LayoutRow {
                            width: layoutColumn.width
                            height: implicitHeight
                        }
                    }
                }

                PageNote {
                    // Only once there is an answer: before the compositor has
                    // been asked, an empty list is silence rather than a fact.
                    visible: HyprInput.ready && HyprInput.layouts.length === 0
                    text: Translation.tr("No layout is set, so the compositor is using its own default")
                }

                PageDivider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledComboBox {
                        id: layoutPicker
                        Layout.fillWidth: true
                        buttonIcon: "keyboard_alt"
                        textRole: "name"
                        model: HyprInput.availableLayouts.filter(layout => HyprInput.layouts.indexOf(layout.code) === -1)
                    }
                    RippleButtonWithIcon {
                        enabled: layoutPicker.model.length > 0
                        materialIcon: "add"
                        mainText: Translation.tr("Add")
                        onClicked: {
                            const chosen = layoutPicker.model[layoutPicker.currentIndex];
                            if (chosen)
                                HyprInput.addLayout(chosen.code);
                            root.syncLayouts();
                        }
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Keys")
            }

            SystemCard {
                Layout.fillWidth: true

                ContentSubsection {
                    title: Translation.tr("Switch layout with")
                    StyledComboBox {
                        id: switchPicker
                        Layout.fillWidth: true
                        buttonIcon: "swap_horiz"
                        textRole: "displayName"
                        model: root.switchOptions
                        currentIndex: {
                            const entry = HyprInput.optionEntry("grp:");
                            const found = root.switchOptions.findIndex(option => option.value === entry);
                            return found !== -1 ? found : 0;
                        }
                        onActivated: index => HyprInput.set(["input"], "kb_options", HyprInput.optionsWith("grp:", root.switchOptions[index].value))
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Caps Lock does")
                    StyledComboBox {
                        id: capsPicker
                        Layout.fillWidth: true
                        buttonIcon: "keyboard_capslock"
                        textRole: "displayName"
                        model: root.capsOptions
                        currentIndex: {
                            const entry = HyprInput.optionEntry("caps:");
                            const found = root.capsOptions.findIndex(option => option.value === entry);
                            return found !== -1 ? found : 0;
                        }
                        onActivated: index => HyprInput.set(["input"], "kb_options", HyprInput.optionsWith("caps:", root.capsOptions[index].value))
                    }
                }

                PageDivider {}

                SettingRow {
                    icon: "keyboard_double_arrow_right"
                    label: Translation.tr("Repeat rate")
                    unit: Translation.tr("/s")
                    from: 1
                    to: 100
                    amount: HyprInput.repeatRate
                    holdWrites: HyprInput.busy
                    onAmountEdited: value => HyprInput.set(["input"], "repeat_rate", value)
                }
                SettingRow {
                    icon: "timer"
                    label: Translation.tr("Repeat starts after")
                    unit: Translation.tr("ms")
                    from: 100
                    to: 2000
                    stepSize: 50
                    amount: HyprInput.repeatDelay
                    holdWrites: HyprInput.busy
                    onAmountEdited: value => HyprInput.set(["input"], "repeat_delay", value)
                }

                ConfigSwitch {
                    id: numlockSwitch
                    text: Translation.tr("Num Lock on at start")
                    buttonIcon: "pin"
                    Binding {
                        target: numlockSwitch
                        property: "checked"
                        value: HyprInput.numlock
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== HyprInput.numlock)
                            HyprInput.set(["input"], "numlock_by_default", checked);
                    }
                }
            }

            PageHeading {
                visible: HyprInput.touchpadDevice.length > 0
                text: Translation.tr("Touchpad")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: HyprInput.touchpadDevice.length > 0

                ConfigSwitch {
                    id: naturalScrollSwitch
                    text: Translation.tr("Content follows the fingers")
                    buttonIcon: "swipe_vertical"
                    Binding {
                        target: naturalScrollSwitch
                        property: "checked"
                        value: HyprInput.touchpadNaturalScroll
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== HyprInput.touchpadNaturalScroll)
                            HyprInput.set(["input", "touchpad"], "natural_scroll", checked);
                    }
                }
                ConfigSwitch {
                    id: dwtSwitch
                    text: Translation.tr("Ignore it while typing")
                    buttonIcon: "block"
                    Binding {
                        target: dwtSwitch
                        property: "checked"
                        value: HyprInput.touchpadDisableWhileTyping
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== HyprInput.touchpadDisableWhileTyping)
                            HyprInput.set(["input", "touchpad"], "disable_while_typing", checked);
                    }
                }
                ConfigSwitch {
                    id: clickfingerSwitch
                    text: Translation.tr("Two fingers for a right click")
                    buttonIcon: "ads_click"
                    Binding {
                        target: clickfingerSwitch
                        property: "checked"
                        value: HyprInput.touchpadClickfinger
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== HyprInput.touchpadClickfinger)
                            HyprInput.set(["input", "touchpad"], "clickfinger_behavior", checked);
                    }
                }

                SettingRow {
                    icon: "swipe_down"
                    label: Translation.tr("Scroll speed")
                    unit: "%"
                    from: 10
                    to: 300
                    stepSize: 5
                    amount: Math.round(HyprInput.touchpadScrollFactor * 100)
                    holdWrites: HyprInput.busy
                    onAmountEdited: value => HyprInput.set(["input", "touchpad"], "scroll_factor", value / 100)
                }
            }

            SystemCard {
                Layout.fillWidth: true
                visible: HyprInput.ready && !HyprInput.writable

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Applied, but not written: custom/general.lua holds this setting in a shape that cannot be edited a line at a time, so it comes back on the next reload.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colError
                }
            }

            PageNote {
                Layout.topMargin: 8
                text: Translation.tr("Applied at once and written into hypr/custom/general.lua, which is sourced after what the shell writes for itself, so what is set here is what wins.")
            }
        }
    }
}
