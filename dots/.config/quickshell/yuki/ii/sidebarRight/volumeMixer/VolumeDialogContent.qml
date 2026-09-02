import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    // A processor's own sink is not a choice: it cannot be adjusted and it is
    // not this panel's to hand the default to. Said in a line below instead,
    // because it is still where the sound goes.
    readonly property list<var> devices: Audio.hardwareDevices(root.isSink)
    readonly property bool hasApps: appPwNodes.length > 0
    readonly property var currentDevice: root.isSink ? Audio.sink : Audio.source
    // The hardware at the end of the chain, so a processor holding the default
    // does not leave the picker showing nothing selected.
    readonly property var defaultEndpoint: root.isSink ? Audio.defaultSinkEndpoint : Audio.defaultSourceEndpoint
    readonly property bool deviceMuted: root.currentDevice?.audio?.muted ?? false
    spacing: 16

    // Naming an application costs a look at its process, so it happens while the
    // mixer is on screen and not for every notification chime. Counted while it
    // is visible rather than while it exists: a swipe view builds every page at
    // once, and an overlay widget that has been dismissed is still alive behind
    // the window it was drawn in, so existing was not the same as being watched.
    readonly property bool watchingStreams: root.visible
    onWatchingStreamsChanged: StreamApps.subscribers += root.watchingStreams ? 1 : -1
    Component.onCompleted: if (root.watchingStreams) StreamApps.subscribers++
    Component.onDestruction: if (root.watchingStreams) StreamApps.subscribers--

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
        // Against the device shown here, not against the processor existing
        // anywhere: this line stands in for the level below and for what the
        // picker is naming, and both of those only change when the processor
        // holds the default. A processor merely present, with the default on
        // hardware, hides nothing and wants no caption.
        visible: root.isSink && Audio.managedByProcessor(root.currentDevice)
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
                    Audio.setDeviceVolume(root.currentDevice, value);
            }
        }
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => item.id === root.defaultEndpoint?.id)
        onActivated: (index) => {
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
            // Choosing an item makes the box write its own index, which drops
            // the binding above -- from then on it shows the choice rather than
            // the device sound actually goes to, and a request pipewire never
            // granted looks exactly like one it did. Putting the binding back
            // costs the box its memory of the click, which is the point.
            deviceSelector.currentIndex = Qt.binding(() => root.devices.findIndex(device => device.id === root.defaultEndpoint?.id))
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
