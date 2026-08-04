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
    // Named on the picker's own button, so an application playing through a
    // processor says so before the list is opened.
    readonly property bool throughProcessor: root.currentDevice !== null && !Audio.isHardware(root.currentDevice)
    // Processors first: for an application they are the "with effects" choice,
    // and the hardware below is "straight out of this instead".
    readonly property list<var> targets: Audio.virtualDevices(root.node?.isSink ?? true).concat(root.devices)

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

    // Both answers in one list, because for one application they are one
    // question: play through the processor, or straight out of a device.
    StyledComboBox {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.targets.length > 1
        buttonIcon: root.throughProcessor ? "graphic_eq" : (root.node?.isSink ? "speaker" : "mic_external_on")
        model: root.targets.map(target => Audio.isHardware(target)
            ? Audio.friendlyDeviceName(target)
            : Translation.tr("Through %1").arg(Audio.friendlyDeviceName(target)))
        currentIndex: root.targets.findIndex(target => target.id === root.currentDevice?.id)
        onActivated: index => Audio.sendStreamTo(root.node, root.targets[index])
    }
}
