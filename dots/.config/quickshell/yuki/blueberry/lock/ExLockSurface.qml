import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

import qs
import qs.core
import qs.core.services
import qs.core.panels.lock
import qs.blueberry.looks

// The lock screen of one monitor: the wallpaper blurred under a light veil, the
// time, and who is signed in with the password field. Locking itself, the
// check and the keyring are the shared lock's. This only draws it and hands it
// what is typed.
MouseArea {
    id: root

    required property LockContext context

    /** 0 to 1 as the lock comes up, back to 0 as it lets go. */
    property real shown: 0
    /** Up at once rather than faded in, for a screen added to a lock already held. */
    property bool appearAtOnce: false
    /** The password in plain letters, for this screen only. */
    property bool reveal: false
    /** Whether Caps Lock is on, which the lock reads for every screen. */
    property bool capsLock: false

    /** A key reached the field, which can have been Caps Lock. */
    signal keyTyped

    function forceFieldFocus() {
        field.input.forceActiveFocus();
    }

    // Focus is taken on showing, on a click and when the lock asks, never on
    // pointer movement: there is one of these per screen, and each taking focus
    // as the pointer passed made two screens hand the field back and forth.
    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
        function onCurrentTextChanged() {
            if (field.text !== root.context.currentText)
                field.text = root.context.currentText;
        }
        function onShowFailureChanged() {
            if (root.context.showFailure)
                shake.restart();
        }
        function onReleasingChanged() {
            if (root.context.releasing) {
                enter.stop();
                leave.start();
                return;
            }
            // Locked again before the lock had let go. Letting go itself
            // clears this too, and the surface is on its way out then.
            if (!GlobalStates.screenLocked)
                return;
            leave.stop();
            if (root.appearAtOnce)
                root.shown = 1;
            else
                enter.start();
        }
    }

    // The compositor keeps drawing the desktop under the lock, so the lock
    // fades in over the windows as the wallpaper blurs, the clock drops in and
    // the card rises. Letting go runs it backwards, down to the desktop itself.
    NumberAnimation {
        id: enter
        target: root
        property: "shown"
        to: 1
        duration: ExLooks.motion.slow
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.enter
    }
    NumberAnimation {
        id: leave
        target: root
        property: "shown"
        to: 0
        duration: ExLooks.motion.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.exit
    }

    acceptedButtons: Qt.LeftButton
    onPressed: root.forceFieldFocus()
    Component.onCompleted: {
        if (root.appearAtOnce)
            root.shown = 1;
        else
            enter.start();
        root.forceFieldFocus();
    }

    Item {
        anchors.fill: parent
        opacity: root.shown

        // Solid under the wallpaper, so nothing of the desktop shows through
        // a lock at rest, even while the wallpaper is still loading.
        Rectangle {
            anchors.fill: parent
            color: ExLooks.colors.background
        }
        Image {
            id: wallpaper
            anchors.fill: parent
            source: Config.options.background.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.width, root.height)
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: wallpaper
            blurEnabled: true
            // Padding lets the blur reach past the image into nothing, which
            // left a pale frame along the screen edges.
            autoPaddingEnabled: false
            blur: root.shown
            blurMax: 64
            saturation: -0.1 * root.shown
        }
        Rectangle {
            anchors.fill: parent
            color: ExLooks.colors.lockVeil
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.14 - 24 * (1 - root.shown)
        opacity: root.shown
        spacing: ExLooks.spacing.xs

        ExText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.time
            font.pixelSize: 96
            font.weight: 300
        }
        ExText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.longDate
            role: "title"
            font.weight: 500
        }
    }

    ExSurface {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shake.offset
        y: parent.height * 0.58 + 32 * (1 - root.shown)
        opacity: root.shown
        scale: 0.96 + 0.04 * root.shown
        width: 360
        height: cardColumn.implicitHeight + 2 * ExLooks.spacing.xl
        radius: ExLooks.radius.panel
        elevation: 2

        ColumnLayout {
            id: cardColumn

            x: ExLooks.spacing.xl
            y: ExLooks.spacing.xl
            width: parent.width - 2 * ExLooks.spacing.xl
            spacing: ExLooks.spacing.m

            ExAvatar {
                Layout.alignment: Qt.AlignHCenter
                size: 72
                plate: ExLooks.colors.tonal
                ink: ExLooks.colors.tonalInk
            }
            ExText {
                Layout.alignment: Qt.AlignHCenter
                text: SystemInfo.username
                role: "title"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.s

                ExTextField {
                    id: field

                    Layout.fillWidth: true
                    glyph: "lock"
                    placeholder: Translation.tr("Password")
                    enabled: !root.context.unlockInProgress
                    input.opacity: enabled ? 1 : 0.6
                    // A wrong password marks the field until the next one is typed.
                    glyphColor: root.context.showFailure ? ExLooks.colors.destructive : ExLooks.colors.textDim
                    border.width: root.context.showFailure || field.input.activeFocus ? 2 : 1
                    border.color: root.context.showFailure ? ExLooks.colors.destructive
                        : field.input.activeFocus ? ExLooks.colors.accent : ExLooks.colors.border

                    Behavior on border.color {
                        ColorAnimation { duration: ExLooks.motion.fast }
                    }

                    // The password being checked, along the field's lower edge.
                    ExProgressLine {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: ExLooks.radius.control
                        anchors.rightMargin: ExLooks.radius.control
                        anchors.bottomMargin: 1
                        height: 2
                        running: root.context.unlockInProgress
                    }

                    onTextChanged: {
                        if (root.context.currentText !== field.text)
                            root.context.currentText = field.text;
                        // A shown password is hidden again once it is gone,
                        // so the next one is not typed out in the open.
                        if (field.text.length === 0)
                            root.reveal = false;
                    }

                    Binding {
                        target: field.input
                        property: "echoMode"
                        value: root.reveal ? TextInput.Normal : TextInput.Password
                    }

                    trailing: [
                        // Caps Lock on, as Windows marks it in the password field.
                        Item {
                            visible: root.capsLock
                            implicitWidth: 28
                            implicitHeight: 28

                            ExGlyph {
                                anchors.centerIn: parent
                                text: "keyboard_capslock_badge"
                                size: 18
                                color: ExLooks.colors.accent
                            }
                        },
                        AbstractButton {
                            id: eye

                            ExPrimaryOnly {
                                z: 1
                            }

                            visible: field.text.length > 0
                            implicitWidth: 28
                            implicitHeight: 28
                            hoverEnabled: true
                            // The field keeps the keys while this is clicked.
                            focusPolicy: Qt.NoFocus
                            onClicked: root.reveal = !root.reveal

                            background: Rectangle {
                                radius: ExLooks.radius.menuItem
                                color: "transparent"

                                ExStateLayer {
                                    ink: ExLooks.colors.text
                                    hovered: eye.hovered
                                    pressed: eye.down
                                }
                            }
                            contentItem: Item {
                                ExGlyph {
                                    anchors.centerIn: parent
                                    text: root.reveal ? "visibility_off" : "visibility"
                                    size: 18
                                    color: ExLooks.colors.textDim
                                }
                            }
                        }
                    ]

                    input.Keys.onPressed: event => {
                        root.keyTyped();
                        root.context.resetClearTimer();
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.context.currentText.length > 0)
                                root.context.tryUnlock();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.context.currentText = "";
                            event.accepted = true;
                        }
                    }
                }
                // Breathing while the reader waits for a finger, faded once
                // it has been given up on until the next lock.
                ExGlyph {
                    id: fingerprint

                    readonly property bool listening: root.context.fingerListening && !root.context.fingerGivenUp

                    visible: root.context.fingerprintsConfigured
                    text: "fingerprint"
                    size: 24
                    color: root.context.fingerGivenUp ? ExLooks.colors.textDim : ExLooks.colors.accent
                    opacity: root.context.fingerGivenUp ? 0.5 : 1

                    SequentialAnimation on opacity {
                        running: fingerprint.listening && fingerprint.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                        onStopped: fingerprint.opacity = Qt.binding(() => root.context.fingerGivenUp ? 0.5 : 1)
                    }
                }
            }
        }
    }

    // A short shake sideways for a wrong password.
    SequentialAnimation {
        id: shake
        property real offset: 0
        NumberAnimation { target: shake; property: "offset"; to: -12; duration: 50 }
        NumberAnimation { target: shake; property: "offset"; to: 10; duration: 70 }
        NumberAnimation { target: shake; property: "offset"; to: -6; duration: 60 }
        NumberAnimation { target: shake; property: "offset"; to: 0; duration: 60 }
    }
}
