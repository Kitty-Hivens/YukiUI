import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects

/**
 * One application in the mixer: its level, and the device carrying it.
 *
 * The device is folded away until asked for. In a panel this narrow a picker
 * per application would take more room than the levels everyone came for.
 */
Item {
    id: root
    required property PwNode node
    property bool choosingDevice: false

    readonly property list<var> devices: Audio.hardwareDevices(root.node?.isSink ?? true)
    readonly property var currentDevice: Audio.deviceOfStream(root.node)
    // A stream a processor holds cannot be sent anywhere from here: it is taken
    // straight back. The panel says where sound goes instead.
    readonly property bool throughProcessor: root.currentDevice !== null && !Audio.isHardware(root.currentDevice)
    // What this application can be sent to: through a processor, or straight
    // out of a device.
    readonly property list<var> targets: Audio.virtualDevices(root.node?.isSink ?? true).concat(root.devices)

    PwObjectTracker {
        objects: [root.node]
    }

    implicitHeight: entryColumn.implicitHeight

    ColumnLayout {
        id: entryColumn
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 2

        RowLayout {
            id: rowLayout
            Layout.fillWidth: true
            spacing: 6

            MouseArea {
                property real size: 36
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                Layout.preferredWidth: size
                Layout.preferredHeight: size

                cursorShape: Qt.PointingHandCursor
                onClicked: root.node.audio.muted = !root.node.audio.muted

                hoverEnabled: true
                property bool hovered: containsMouse
                StyledToolTip {
                    text: root.node?.audio.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
                }

                StyledImage {
                    id: iconImg
                    anchors.fill: parent
                    visible: false
                    source: {
                        // The application's own icon first: a stream carrying
                        // "chromium-browser" is describing the runtime.
                        const own = StreamApps.iconFor(root.node);
                        if (AppSearch.iconExists(own))
                            return Quickshell.iconPath(own, "image-missing");
                        let icon;
                        icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                        if (AppSearch.iconExists(icon))
                            return Quickshell.iconPath(icon, "image-missing");
                        icon = AppSearch.guessIcon(root.node?.properties["node.name"] ?? "");
                        return Quickshell.iconPath(icon, "image-missing");
                    }
                }

                Desaturate {
                    anchors.fill: iconImg
                    source: iconImg
                    desaturation: root.node?.audio.muted ? 1.0 : 0.0
                    visible: iconImg.source !== ""
                    opacity: root.node?.audio.muted ? 0.4 : 1.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                    Behavior on desaturation {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.node?.audio.muted ?? false
                    text: root.node?.isSink ? "volume_off" : "mic_off"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -4

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        const app = Audio.appNodeDisplayName(root.node);
                        const context = Audio.appNodeContext(root.node);
                        return context.length > 0 ? `${app} • ${context}` : app;
                    }
                }

                // The button belongs beside the slider, not beside the whole
                // entry: centred against name and slider together it sat a line
                // above the control it works with.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledSlider {
                        id: slider
                        Layout.fillWidth: true
                        value: root.node?.audio.volume ?? 0
                        onMoved: root.node.audio.volume = value
                        configuration: StyledSlider.Configuration.S
                    }

                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        toggled: root.choosingDevice
                        visible: root.targets.length > 1
                        onClicked: root.choosingDevice = !root.choosingDevice
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.throughProcessor ? "graphic_eq" : (root.node?.isSink ? "speaker" : "mic_external_on")
                            iconSize: 19
                            color: root.choosingDevice ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                        StyledToolTip {
                            text: root.currentDevice
                                ? Translation.tr("Playing on %1").arg(Audio.friendlyDeviceName(root.currentDevice))
                                : Translation.tr("Choose a device")
                        }
                    }
                }
            }
        }

        Revealer {
            Layout.fillWidth: true
            vertical: true
            reveal: root.choosingDevice

            ColumnLayout {
                width: entryColumn.width
                spacing: 2

                Repeater {
                    model: root.targets

                    delegate: RippleButton {
                        id: deviceButton
                        required property var modelData
                        readonly property bool current: modelData.id === root.currentDevice?.id
                        Layout.fillWidth: true
                        Layout.leftMargin: 36
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        toggled: deviceButton.current
                        // The default toggled fill is the primary colour, which
                        // this row's text is not written for.
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            Audio.sendStreamTo(root.node, deviceButton.modelData);
                            root.choosingDevice = false;
                        }

                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                Layout.leftMargin: 8
                                text: deviceButton.current ? "check" : ""
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.rightMargin: 8
                                horizontalAlignment: Text.AlignLeft
                                text: Audio.isHardware(deviceButton.modelData)
                                    ? Audio.friendlyDeviceName(deviceButton.modelData)
                                    : Translation.tr("Through %1").arg(Audio.friendlyDeviceName(deviceButton.modelData))
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: deviceButton.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }
}
