pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.common

/**
 * What BlueZ is asking, and the two answers it takes.
 *
 * Seven questions share one screen because they are one question wearing
 * different clothes -- is this device you, yes or no. What changes between them
 * is whether the code is read here or typed here, and whether refusing is
 * called cancelling or denying.
 */
Item {
    id: root

    readonly property string deviceName: BluetoothAgent.request?.name || Translation.tr("Unknown device")
    readonly property bool typing: BluetoothAgent.awaitingInput

    readonly property string heading: BluetoothAgent.kind === "service"
        ? Translation.tr("Let %1 connect?").arg(root.deviceName)
        : Translation.tr("Pair with %1?").arg(root.deviceName)

    readonly property string message: {
        if (BluetoothAgent.kind === "confirm")
            return Translation.tr("Check that this same code is showing on the device");
        if (BluetoothAgent.kind === "authorize")
            return Translation.tr("%1 is asking to pair with this computer").arg(BluetoothAgent.request?.address ?? "");
        if (BluetoothAgent.showingCode)
            return Translation.tr("Type this code on the device");
        if (BluetoothAgent.kind === "passkey")
            return Translation.tr("Type the code showing on the device");
        if (BluetoothAgent.kind === "pin")
            return Translation.tr("Type the PIN the device is set to");
        if (BluetoothAgent.kind === "service")
            return Translation.tr("It is asking to use %1").arg(BluetoothAgent.services.join(", "));
        return "";
    }

    function submit() {
        if (root.typing && inputField.text.length === 0)
            return;
        BluetoothAgent.accept(root.typing ? inputField.text : "");
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            BluetoothAgent.reject();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    WindowDialog {
        id: dialog
        anchors.centerIn: parent
        // Wide enough for its own buttons. Three answers in a language that
        // spells them out is wider than the card, and the row was drawn over
        // the edge of it rather than being allowed to set the width.
        backgroundWidth: Math.max(450, buttonRow.implicitWidth + Appearance.rounding.large * 2)
        show: false
        Component.onCompleted: show = true
        onDismiss: BluetoothAgent.reject()

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: 26
            text: Icons.getBluetoothDeviceMaterialSymbol(BluetoothAgent.request?.icon ?? "")
            color: Appearance.colors.colSecondary
        }

        WindowDialogTitle {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.heading
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.message
        }

        // The code, a character at a time, so the ones already typed on the far
        // end can be told apart from the ones still to come -- which is the only
        // sign this screen gets that anything is happening over there.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            visible: BluetoothAgent.code.length > 0
            spacing: 2

            Repeater {
                model: BluetoothAgent.code.split("")

                delegate: StyledText {
                    required property string modelData
                    required property int index
                    text: modelData
                    // Larger than anything on the scale: it is meant to be read
                    // off the screen from arm's length and compared.
                    font.pixelSize: 34
                    font.family: Appearance.font.family.numbers
                    color: index < BluetoothAgent.entered
                        ? Appearance.colors.colSubtext
                        : Appearance.colors.colOnLayer2
                }
            }
        }

        MaterialTextField {
            id: inputField
            Layout.fillWidth: true
            visible: root.typing
            focus: root.typing
            placeholderText: BluetoothAgent.kind === "pin" ? Translation.tr("PIN") : Translation.tr("Code")
            inputMethodHints: BluetoothAgent.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
            onAccepted: root.submit()

            Component.onCompleted: if (root.typing) forceActiveFocus()

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    BluetoothAgent.reject();
                    event.accepted = true;
                }
            }
        }

        WindowDialogButtonRow {
            id: buttonRow
            Layout.bottomMargin: 10

            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: BluetoothAgent.kind === "service" ? Translation.tr("Deny") : Translation.tr("Cancel")
                onClicked: BluetoothAgent.reject()
            }
            DialogButton {
                // A shown code is not something to agree to. It is answered by
                // being typed on the other device, and the only thing left to
                // decide here is whether to give up on it.
                visible: !BluetoothAgent.showingCode
                enabled: !root.typing || inputField.text.length > 0
                buttonText: BluetoothAgent.kind === "service" ? Translation.tr("Allow once") : Translation.tr("Pair")
                onClicked: root.submit()
            }
            // Answering about the device instead of about this one profile, and
            // the answer worth offering: a device asks once per profile it
            // wants, and asks again every time it comes back.
            DialogButton {
                visible: BluetoothAgent.kind === "service"
                buttonText: Translation.tr("Always allow")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: BluetoothAgent.acceptAlways()
            }
        }
    }
}
