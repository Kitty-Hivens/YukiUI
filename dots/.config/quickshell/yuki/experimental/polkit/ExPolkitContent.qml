import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks
import qs.experimental.motion

// An application asking for administrator rights: what it wants to do, the
// password, and the choice to allow it or not. Enter allows, Escape refuses,
// and a wrong password shakes the card and says so.
Item {
    id: root

    readonly property bool usePasswordChars: !(PolkitService.flow?.responseVisible ?? false)
    property bool failed: false

    Component.onCompleted: field.input.forceActiveFocus()

    Connections {
        target: PolkitService.flow
        function onAuthenticationFailed() {
            root.failed = true;
            field.text = "";
            shake.restart();
            field.input.forceActiveFocus();
        }
        // A further question in the same request starts from an empty field,
        // not from the answer to the one before.
        function onIsResponseRequiredChanged() {
            if (!PolkitService.flow.isResponseRequired)
                return;
            field.text = "";
            field.input.forceActiveFocus();
        }
    }

    Binding {
        target: field.input
        property: "echoMode"
        value: root.usePasswordChars ? TextInput.Password : TextInput.Normal
    }

    ExPresence {
        id: presence
        wanted: PolkitService.active
    }

    Rectangle {
        anchors.fill: parent
        color: ExLooks.colors.scrim
        opacity: presence.progress
    }

    // A click outside the card does not answer the request.
    MouseArea {
        anchors.fill: parent
        onPressed: field.input.forceActiveFocus()
    }

    ExSurface {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: shake.offset
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

            ExGlyph {
                Layout.alignment: Qt.AlignHCenter
                text: "shield_lock"
                size: 40
                fill: 1
                color: ExLooks.colors.accent
            }
            ExText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Authentication required")
                role: "title"
            }
            ExText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 4
                text: PolkitService.cleanMessage
                dim: true
            }

            ExTextField {
                id: field

                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                glyph: "key"
                placeholder: PolkitService.cleanPrompt
                enabled: PolkitService.interactionAvailable
                opacity: enabled ? 1 : 0.6
                onTextChanged: {
                    if (field.text.length > 0)
                        root.failed = false;
                }

                input.Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (PolkitService.interactionAvailable)
                            PolkitService.submit(field.text);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        PolkitService.cancel();
                        event.accepted = true;
                    }
                }
            }
            ExText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.failed
                text: Translation.tr("Incorrect password")
                role: "caption"
                color: ExLooks.colors.destructive
            }
            // What PAM says besides the question: to touch the reader, that the
            // account is locked, how many tries are left.
            ExText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: text.length > 0
                text: PolkitService.flow?.supplementaryMessage ?? ""
                role: "caption"
                color: PolkitService.flow?.supplementaryIsError ? ExLooks.colors.destructive : ExLooks.colors.textDim
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.s

                ExButton {
                    Layout.fillWidth: true
                    kind: "control"
                    text: Translation.tr("Cancel")
                    onClicked: PolkitService.cancel()
                }
                ExButton {
                    Layout.fillWidth: true
                    kind: "accent"
                    text: Translation.tr("OK")
                    enabled: PolkitService.interactionAvailable
                    onClicked: PolkitService.submit(field.text)
                }
            }
        }
    }

    SequentialAnimation {
        id: shake
        property real offset: 0
        NumberAnimation { target: shake; property: "offset"; to: -12; duration: 50 }
        NumberAnimation { target: shake; property: "offset"; to: 10; duration: 70 }
        NumberAnimation { target: shake; property: "offset"; to: -6; duration: 60 }
        NumberAnimation { target: shake; property: "offset"; to: 0; duration: 60 }
    }
}
