import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.core.services
import qs.experimental.looks
import qs.experimental.motion

// An application asking for administrator rights: what it wants to do, the
// password, and the choice to allow it or not. Enter allows, Escape refuses,
// and a wrong password shakes the card and says so.
Item {
    id: root

    /** What the cards on all screens share: the text typed, and a refusal. */
    required property var prompt
    readonly property bool usePasswordChars: !(PolkitService.flow?.responseVisible ?? false)
    property bool choosing: false

    Component.onCompleted: {
        field.text = root.prompt.typed;
        field.input.forceActiveFocus();
    }

    Connections {
        target: root.prompt
        function onTypedChanged() {
            if (field.text !== root.prompt.typed)
                field.text = root.prompt.typed;
        }
        function onRefused() {
            shake.restart();
            field.input.forceActiveFocus();
        }
    }
    Connections {
        target: PolkitService
        function onFlowChanged() {
            root.choosing = false;
        }
    }
    Connections {
        target: PolkitService.flow
        function onIsResponseRequiredChanged() {
            if (PolkitService.flow.isResponseRequired)
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

            // Whose password it is. With more than one account that would do,
            // it opens a list of them to pick from.
            AbstractButton {
                id: account

                readonly property var identity: PolkitService.flow?.selectedIdentity ?? null
                readonly property bool canChoose: PolkitService.identities.length > 1

                ExPrimaryOnly {
                    z: 1
                }

                Layout.alignment: Qt.AlignHCenter
                visible: account.identity !== null && !account.identity.isGroup
                enabled: account.canChoose
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                implicitWidth: accountRow.implicitWidth + 2 * ExLooks.spacing.s
                implicitHeight: ExLooks.sizes.menuItem
                onClicked: root.choosing = !root.choosing

                background: Rectangle {
                    radius: ExLooks.radius.menuItem
                    color: "transparent"

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: account.hovered && account.canChoose
                        pressed: account.down
                    }
                }
                contentItem: Item {
                    RowLayout {
                        id: accountRow
                        anchors.centerIn: parent
                        spacing: ExLooks.spacing.s

                        ExGlyph {
                            text: "person"
                            size: 18
                            color: ExLooks.colors.textDim
                        }
                        ExText {
                            text: account.identity?.displayName ?? ""
                        }
                        ExGlyph {
                            visible: account.canChoose
                            text: root.choosing ? "expand_less" : "expand_more"
                            size: 18
                            color: ExLooks.colors.textDim
                        }
                    }
                }
            }
            ExMenu {
                Layout.alignment: Qt.AlignHCenter
                visible: root.choosing && account.canChoose
                elevation: 0
                color: ExLooks.colors.surfaceSunken

                Repeater {
                    model: PolkitService.identities

                    ExMenuItem {
                        required property var modelData

                        glyph: modelData === account.identity ? "check" : ""
                        text: modelData.displayName === modelData.string
                            ? modelData.string : `${modelData.displayName} (${modelData.string})`
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.choosing = false;
                            PolkitService.chooseIdentity(modelData);
                            field.input.forceActiveFocus();
                        }
                    }
                }
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
                    if (root.prompt.typed !== field.text)
                        root.prompt.typed = field.text;
                    if (field.text.length > 0)
                        root.prompt.failed = false;
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
                visible: root.prompt.failed
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
