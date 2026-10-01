import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.experimental.looks
import qs.experimental.motion

// A Bluetooth device asking to pair or to connect: which device, what it wants,
// the code to compare or to type when there is one, and the answer. Enter
// accepts, Escape refuses.
Item {
    id: root

    readonly property string deviceName: BluetoothAgent.request?.name || Translation.tr("Unknown device")
    readonly property bool typing: BluetoothAgent.awaitingInput
    readonly property string heading: BluetoothAgent.kind === "service"
        ? Translation.tr("Let %1 connect?").arg(root.deviceName)
        : Translation.tr("Pair with %1?").arg(root.deviceName)
    readonly property string explanation: {
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

    function accept() {
        if (BluetoothAgent.showingCode || (root.typing && field.text.length === 0))
            return;
        BluetoothAgent.accept(root.typing ? field.text : "");
    }

    /**
     * Gets the card ready for the question now on screen.
     *
     * The card stays up while BlueZ has more to ask, so it is not built again
     * for the next question: the field kept the previous PIN, and focus stayed
     * where the previous kind wanted it, on a field now hidden or on the card
     * while a field was now waiting to be typed into.
     */
    function prepare() {
        field.text = "";
        if (root.typing)
            field.input.forceActiveFocus();
        else
            root.forceActiveFocus();
    }

    readonly property var requestId: BluetoothAgent.request?.id ?? null
    onRequestIdChanged: {
        if (root.requestId !== null)
            root.prepare();
    }

    focus: true
    Component.onCompleted: root.prepare()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            BluetoothAgent.reject();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.accept();
            event.accepted = true;
        }
    }

    ExPresence {
        id: presence
        wanted: BluetoothAgent.active
    }

    Rectangle {
        anchors.fill: parent
        color: ExLooks.colors.scrim
        opacity: presence.progress
    }

    MouseArea {
        anchors.fill: parent
    }

    ExSurface {
        anchors.centerIn: parent
        opacity: presence.progress
        scale: 0.94 + 0.06 * presence.progress
        width: 420
        height: column.implicitHeight + 2 * ExLooks.spacing.xl
        radius: ExLooks.radius.panel
        elevation: 2

        ColumnLayout {
            id: column

            x: ExLooks.spacing.xl
            y: ExLooks.spacing.xl
            width: parent.width - 2 * ExLooks.spacing.xl
            spacing: ExLooks.spacing.m

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: ExLooks.colors.tonal

                ExGlyph {
                    anchors.centerIn: parent
                    text: Icons.getBluetoothDeviceMaterialSymbol(BluetoothAgent.request?.icon ?? "")
                    size: 32
                    color: ExLooks.colors.tonalInk
                }
            }
            ExText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.heading
                role: "title"
            }
            ExText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: text.length > 0
                text: root.explanation
                dim: true
            }

            // The code to compare, or to type on the device, digit by digit,
            // the ones already typed there marked as they arrive.
            Row {
                Layout.alignment: Qt.AlignHCenter
                visible: BluetoothAgent.code.length > 0
                spacing: ExLooks.spacing.xs

                Repeater {
                    model: BluetoothAgent.code.split("")

                    Rectangle {
                        required property string modelData
                        required property int index
                        width: 36
                        height: 44
                        radius: ExLooks.radius.control
                        color: index < BluetoothAgent.entered ? ExLooks.colors.tonal : ExLooks.colors.surfaceSunken

                        ExText {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 22
                            font.weight: 600
                            color: index < BluetoothAgent.entered ? ExLooks.colors.tonalInk : ExLooks.colors.text
                        }
                    }
                }
            }

            ExTextField {
                id: field

                Layout.fillWidth: true
                visible: root.typing
                glyph: "pin"
                placeholder: BluetoothAgent.kind === "pin" ? Translation.tr("PIN") : Translation.tr("Code")
                input.inputMethodHints: BluetoothAgent.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                input.Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        BluetoothAgent.reject();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.accept();
                        event.accepted = true;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.s

                ExButton {
                    Layout.fillWidth: true
                    kind: "control"
                    text: BluetoothAgent.kind === "service" ? Translation.tr("Deny") : Translation.tr("Cancel")
                    onClicked: BluetoothAgent.reject()
                }
                ExButton {
                    Layout.fillWidth: true
                    visible: BluetoothAgent.kind === "service"
                    kind: "tonal"
                    text: Translation.tr("Always allow")
                    onClicked: BluetoothAgent.acceptAlways()
                }
                ExButton {
                    Layout.fillWidth: true
                    visible: !BluetoothAgent.showingCode
                    kind: "accent"
                    text: BluetoothAgent.kind === "service" ? Translation.tr("Allow once") : Translation.tr("Pair")
                    onClicked: root.accept()
                }
            }
        }
    }
}
