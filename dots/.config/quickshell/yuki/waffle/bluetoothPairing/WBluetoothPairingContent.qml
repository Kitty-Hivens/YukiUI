pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks

/**
 * What BlueZ is asking, in the family's own dialog.
 *
 * The same pane the family answers polkit in, for the same reason: a question
 * the session cannot get past until it is answered. Windows itself puts pairing
 * in a toast rather than a modal, which is a different surface and a separate
 * piece of work.
 */
Rectangle {
    id: root

    color: "#000000"

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

    StyledImage {
        anchors.fill: parent
        source: Config.options.background.wallpaperPath
        fillMode: Image.PreserveAspectCrop

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize("#000000", 0.31)

            PairingDialog {
                id: dialog
                DragHandler {
                    target: null
                    property real startX: dialog.x
                    property real startY: dialog.y
                    onActiveChanged: {
                        if (!active)
                            return;
                        startX = dialog.x;
                        startY = dialog.y;
                    }
                    xAxis.onActiveValueChanged: {
                        dialog.x = Math.round(startX + xAxis.activeValue);
                    }
                    yAxis.onActiveValueChanged: {
                        dialog.y = Math.round(startY + yAxis.activeValue);
                    }
                }
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
            }
        }
    }

    component PairingDialog: WPane {
        borderColor: Looks.colors.ambientShadow

        contentItem: WPanelPageColumn {
            PairingDialogHeader {
                Layout.fillWidth: true
            }
            BodyRectangle {
                implicitHeight: bodyContent.implicitHeight + 48
                implicitWidth: 434
                color: Looks.colors.bg1Base

                ColumnLayout {
                    id: bodyContent
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 20

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15

                        FluentIcon {
                            icon: WIcons.bluetoothDeviceIcon(BluetoothAgent.request?.icon ?? "")
                            implicitSize: 24
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            WText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                font.pixelSize: Looks.font.pixelSize.larger
                                font.weight: Looks.font.weight.strongest
                                text: root.deviceName
                                textFormat: Text.PlainText
                            }
                            WText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                visible: text.length > 0
                                color: Looks.colors.subfg
                                text: BluetoothAgent.request?.address ?? ""
                            }
                        }
                    }

                    WText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignLeft
                        text: root.message
                    }

                    // A character at a time, so the digits already typed on the
                    // far end read differently from the ones still to come --
                    // the only sign this screen gets that anything is happening
                    // over there.
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: BluetoothAgent.code.length > 0
                        spacing: 2

                        Repeater {
                            model: BluetoothAgent.code.split("")

                            delegate: WText {
                                required property string modelData
                                required property int index
                                text: modelData
                                // Off the family's scale, which tops out at 17:
                                // this is meant to be compared with a second
                                // screen at arm's length.
                                font.pixelSize: 32
                                color: index < BluetoothAgent.entered ? Looks.colors.subfg : Looks.colors.fg
                            }
                        }
                    }

                    WTextField {
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
                }
            }
            BodyRectangle {
                implicitHeight: 80
                color: Looks.colors.bgPanelFooterBackground

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 8
                    uniformCellSizes: true

                    // Answering about the device instead of about this one
                    // profile: a device asks once per profile it wants, and
                    // asks again every time it comes back.
                    WButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        horizontalAlignment: Text.AlignHCenter
                        checked: true
                        visible: BluetoothAgent.kind === "service"
                        text: Translation.tr("Always allow")
                        onClicked: BluetoothAgent.acceptAlways()
                    }
                    WButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        colBackground: Looks.colors.bg1
                        horizontalAlignment: Text.AlignHCenter
                        // A shown code is not something to agree to: it is
                        // answered by being typed on the other device.
                        visible: !BluetoothAgent.showingCode
                        enabled: !root.typing || inputField.text.length > 0
                        text: BluetoothAgent.kind === "service" ? Translation.tr("Allow once") : Translation.tr("Pair")
                        onClicked: root.submit()
                    }
                    WButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        colBackground: Looks.colors.bg1
                        horizontalAlignment: Text.AlignHCenter
                        checked: BluetoothAgent.kind !== "service"
                        text: BluetoothAgent.kind === "service" ? Translation.tr("Deny") : Translation.tr("Cancel")
                        onClicked: BluetoothAgent.reject()
                    }
                }
            }
        }
    }

    component PairingDialogHeader: BodyRectangle {
        implicitHeight: headerContent.implicitHeight
        color: Looks.colors.bg2Base

        CloseButton {
            anchors {
                top: parent.top
                right: parent.right
            }
            radius: 0
            implicitWidth: 32
            implicitHeight: 32

            onClicked: BluetoothAgent.reject()
        }

        ColumnLayout {
            id: headerContent
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 18

            WText {
                Layout.topMargin: 20
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                text: Translation.tr("Bluetooth")
            }
            WText {
                Layout.fillWidth: true
                Layout.bottomMargin: 12
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                text: root.heading
                font.pixelSize: Looks.font.pixelSize.xlarger
                font.weight: Looks.font.weight.strongest
            }
        }
    }
}
