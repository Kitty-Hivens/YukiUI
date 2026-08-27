pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.common

/**
 * One numbered setting as a row: what it is, how much of it, and -- where the
 * thing can be called off entirely -- whether it happens at all.
 *
 * The switch column is held open on rows that have no switch, so every number in
 * a card lines up with the ones above and below it. This is a setting; the way
 * into a whole section of them is a [SectionRow].
 */
RowLayout {
    id: settingRow

    required property string icon
    required property string label
    property string note: ""
    property bool noteIsProblem: false
    property string unit: ""
    /** Whether what the row describes is in force. Dims it and holds the number still when it is not. */
    property bool active: true
    /** Set while a write is settling, so a settled number waits rather than being dropped. */
    property bool holdWrites: false
    property bool switchable: false
    property bool switchOn: false
    property bool switchEnabled: true
    property alias from: rowSpin.from
    property alias to: rowSpin.to
    property alias stepSize: rowSpin.stepSize
    property int amount: 0
    /** Once the number has settled rather than once per step. */
    signal amountEdited(int amount)
    signal switched(bool on)

    Layout.fillWidth: true
    Layout.topMargin: 8
    Layout.bottomMargin: 8
    // The same inset a ConfigSwitch gets from being a button, so a row of
    // this kind and a row of that one start and end on the same two lines.
    Layout.leftMargin: 6
    Layout.rightMargin: 6
    spacing: 10

    OptionalMaterialSymbol {
        icon: settingRow.icon
        opacity: settingRow.active ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: settingRow.label
            elide: Text.ElideRight
            color: Appearance.colors.colOnSecondaryContainer
            opacity: settingRow.active ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            visible: settingRow.note.length > 0
            text: settingRow.note
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: settingRow.noteIsProblem ? Appearance.colors.colError : Appearance.colors.colSubtext
        }
    }

    StyledSpinBox {
        id: rowSpin
        enabled: settingRow.active
        stepSize: 1
        // Restated through Binding: the box writes its own value when used,
        // which drops the binding, and what is written is what decides.
        Binding {
            target: rowSpin
            property: "value"
            value: settingRow.amount
            restoreMode: Binding.RestoreBindingOrValue
        }
        // Settled rather than per step. The box is editable, so typing "45"
        // passes through 4, and stepping from 5 to 15 is ten stops -- each of
        // which would be written out and acted on.
        onValueChanged: {
            if (value !== settingRow.amount)
                commitTimer.restart();
        }

        Timer {
            id: commitTimer
            interval: 600
            onTriggered: {
                if (settingRow.holdWrites) {
                    restart();
                    return;
                }
                if (rowSpin.value !== settingRow.amount)
                    settingRow.amountEdited(rowSpin.value);
            }
        }
    }

    StyledText {
        visible: settingRow.unit.length > 0
        text: settingRow.unit
        color: Appearance.colors.colSubtext
        opacity: settingRow.active ? 1 : 0.4
    }

    StyledSwitch {
        id: rowSwitch
        visible: settingRow.switchable
        enabled: settingRow.switchEnabled
        Binding {
            target: rowSwitch
            property: "checked"
            value: settingRow.switchOn
            restoreMode: Binding.RestoreBindingOrValue
        }
        onToggled: settingRow.switched(checked)
    }
    Item {
        // Holds the switch column open on rows that have no switch.
        visible: !settingRow.switchable
        implicitWidth: rowSwitch.implicitWidth
        implicitHeight: 1
    }
}
