pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.common

/**
 * One bluetooth device: what it is, how it stands, and the two things that can
 * be done with it.
 *
 * Pairing and connecting are separate on purpose, because they are separate to
 * the adapter: a device can be remembered and not in use, and forgetting one is
 * not the same as switching it off.
 */
ColumnLayout {
    id: root
    required property BluetoothDevice device
    property bool expanded: false

    readonly property bool connected: root.device?.connected ?? false
    readonly property bool paired: root.device?.paired ?? false
    readonly property bool busy: (root.device?.state ?? BluetoothDeviceState.Disconnected) === BluetoothDeviceState.Connecting
        || (root.device?.state ?? BluetoothDeviceState.Disconnected) === BluetoothDeviceState.Disconnecting

    readonly property string statusText: {
        if (root.busy)
            return root.connected ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
        if (!root.paired)
            return Translation.tr("Not paired");
        const base = root.connected ? Translation.tr("Connected") : Translation.tr("Paired");
        if (!root.connected || !(root.device?.batteryAvailable ?? false))
            return base;
        return `${base} · ${Math.round((root.device?.battery ?? 0) * 100)}%`;
    }

    spacing: 0

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 54
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        onClicked: root.expanded = !root.expanded

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 12

            MaterialSymbol {
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                iconSize: Appearance.font.pixelSize.hugeass
                color: root.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.device?.name || Translation.tr("Unknown device")
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: root.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.bottomMargin: root.expanded ? 8 : 0
        visible: root.expanded
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                // The address, because two headsets of the same model are the same
                // name and nothing else.
                text: root.device?.address ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            DialogButton {
                visible: root.paired
                buttonText: Translation.tr("Forget")
                // A destructive text button: the label carries the warning and the
                // background takes a state layer rather than a red fill.
                colText: Appearance.colors.colError
                colBackground: ColorUtils.transparentize(Appearance.colors.colError, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.92)
                colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.88)
                onClicked: root.device?.forget()
            }
            RippleButtonWithIcon {
                enabled: !root.busy
                materialIcon: root.busy ? "hourglass" : root.connected ? "bluetooth_disabled" : "bluetooth_connected"
                mainText: root.busy ? root.statusText
                    : root.connected ? Translation.tr("Disconnect")
                    : root.paired ? Translation.tr("Connect")
                    : Translation.tr("Pair")
                onClicked: {
                    if (root.connected)
                        root.device?.disconnect();
                    else if (root.paired)
                        root.device?.connect();
                    else
                        BluetoothStatus.pair(root.device);
                }
            }
        }
    }
}
