pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One application's audio: how loud it is and which device carries it.
 *
 * Volume above a hundred exists here and not on a device, because quiet source
 * material is an application's problem, while pushing a card past its own
 * ceiling is how speakers start distorting.
 */
ColumnLayout {
    id: root
    required property PwNode node

    readonly property list<var> devices: Audio.hardwareDevices(root.node?.isSink ?? true)
    readonly property var currentDevice: Audio.deviceOfStream(root.node)
    readonly property bool muted: root.node?.audio?.muted ?? false
    // Inside a processor the choice is not this panel's to make: the processor
    // takes every stream back the moment it is moved. What it plays through is
    // stated instead, and the choice appears again once it plays out directly.
    readonly property bool throughProcessor: root.currentDevice !== null && !Audio.isHardware(root.currentDevice)
    readonly property var endpoint: root.throughProcessor ? Audio.endpointOf(root.currentDevice) : null

    PwObjectTracker {
        objects: [root.node]
    }

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RippleButton {
            implicitWidth: 38
            implicitHeight: 38
            buttonRadius: Appearance.rounding.full
            onClicked: {
                if (root.node?.audio)
                    root.node.audio.muted = !root.node.audio.muted;
            }
            contentItem: Item {
                anchors.fill: parent

                StyledImage {
                    id: appIcon
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    opacity: root.muted ? 0.4 : 1
                    source: {
                        // The application's own icon first: a stream carrying
                        // "chromium-browser" is describing the runtime.
                        const own = StreamApps.iconFor(root.node);
                        if (AppSearch.iconExists(own))
                            return Quickshell.iconPath(own, "image-missing");
                        const named = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                        if (AppSearch.iconExists(named))
                            return Quickshell.iconPath(named, "image-missing");
                        return Quickshell.iconPath(AppSearch.guessIcon(root.node?.properties["node.name"] ?? ""), "image-missing");
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.muted
                    text: root.node?.isSink ? "volume_off" : "mic_off"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer2
                }
            }
            StyledToolTip {
                text: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Audio.appNodeDisplayName(root.node)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                // What is playing, when the application says so: two Firefox
                // tabs are otherwise the same entry twice.
                visible: text.length > 0
                text: Audio.appNodeContext(root.node)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            text: `${Math.round((root.node?.audio?.volume ?? 0) * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    StyledSlider {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        configuration: StyledSlider.Configuration.S
        from: 0
        to: 1.5
        stopIndicatorValues: [1]
        value: root.node?.audio?.volume ?? 0
        onMoved: {
            if (root.node?.audio)
                root.node.audio.volume = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.leftMargin: 4
        visible: root.throughProcessor
        // Both halves of the answer: what it is processed by, and what it comes
        // out of once it has been.
        text: root.endpoint
            ? `${Translation.tr("Through %1").arg(Audio.friendlyDeviceName(root.currentDevice))} → ${Audio.friendlyDeviceName(root.endpoint)}`
            : Translation.tr("Through %1").arg(Audio.friendlyDeviceName(root.currentDevice))
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colSubtext
    }

    StyledComboBox {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: !root.throughProcessor && root.devices.length > 1
        buttonIcon: root.node?.isSink ? "speaker" : "mic_external_on"
        model: root.devices.map(device => Audio.friendlyDeviceName(device))
        currentIndex: root.devices.findIndex(device => device.id === root.currentDevice?.id)
        onActivated: index => AudioRouting.moveStream(root.node, root.devices[index])
    }
}
