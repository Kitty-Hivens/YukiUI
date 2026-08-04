import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    // A processor's own sink is not a choice: it cannot be adjusted and it is
    // not this panel's to hand the default to. Said in a line below instead,
    // because it is still where the sound goes.
    readonly property list<var> devices: Audio.selectableDevices(root.isSink)
    readonly property bool hasApps: appPwNodes.length > 0
    readonly property var currentDevice: root.isSink ? Audio.sink : Audio.source
    readonly property bool deviceMuted: root.currentDevice?.audio?.muted ?? false
    spacing: 16

    // Naming an application costs a look at its process, so it happens while
    // the mixer is open and not for every notification chime.
    Component.onCompleted: StreamApps.subscribers++
    Component.onDestruction: StreamApps.subscribers--

    DialogSectionListView {
        Layout.fillHeight: true
        topMargin: 14

        model: ScriptModel {
            values: root.appPwNodes
        }
        delegate: VolumeMixerEntry {
            anchors {
                left: parent?.left
                right: parent?.right
            }
            required property var modelData
            node: modelData
        }
        PagePlaceholder {
            icon: "widgets"
            title: Translation.tr("No applications")
            shown: !root.hasApps
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }

    // The device's own level, which the mixer never offered: every slider above
    // is a share of this one, and the way to it was another window.
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: root.isSink && Audio.processorInPath
        text: Translation.tr("Sound passes through EasyEffects")
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: root.currentDevice !== null && !Audio.managedByProcessor(root.currentDevice)

        RippleButton {
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            onClicked: {
                if (root.currentDevice?.audio)
                    root.currentDevice.audio.muted = !root.currentDevice.audio.muted;
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: root.isSink
                    ? (root.deviceMuted ? "volume_off" : "volume_up")
                    : (root.deviceMuted ? "mic_off" : "mic")
                iconSize: 20
                color: root.deviceMuted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            }
            StyledToolTip {
                text: root.deviceMuted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.S
            from: 0
            to: 1
            value: root.currentDevice?.audio?.volume ?? 0
            onMoved: {
                if (root.currentDevice?.audio)
                    root.currentDevice.audio.volume = value;
            }
        }
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => {
            if (root.isSink) {
                return item.id === Pipewire.defaultAudioSink?.id
            } else {
                return item.id === Pipewire.defaultAudioSource?.id
            }
        })
        onActivated: (index) => {
            print(index)
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
        }
    }

    component DialogSectionListView: StyledListView {
        Layout.fillWidth: true
        Layout.topMargin: -22
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        topMargin: 12
        bottomMargin: 12
        leftMargin: 20
        rightMargin: 20

        clip: true
        spacing: 4
        animateAppearance: false
    }

    Component {
        id: listElementComp
        ListElement {}
    }
}
