pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One sound device: what it is, how loud it is, which socket it uses, and
 * whether new sound goes here.
 */
ColumnLayout {
    id: root
    required property PwNode node
    required property bool isDefault

    signal defaultRequested

    readonly property var ports: AudioRouting.portsFor(root.node)
    readonly property bool muted: root.node?.audio?.muted ?? false
    // A processor's own device: listed, adjustable, but not something to hand
    // the default over to by hand.
    readonly property bool managed: Audio.managedByProcessor(root.node)

    // Without this the volume and the mute of a device nobody is playing to
    // are never delivered, and the row shows zero.
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
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: root.node?.isSink
                    ? (root.muted ? "volume_off" : "volume_up")
                    : (root.muted ? "mic_off" : "mic")
                iconSize: 22
                color: root.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
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
                text: Audio.friendlyDeviceName(root.node)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: root.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0 && text !== Audio.friendlyDeviceName(root.node)
                text: root.node?.description ?? ""
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

        RippleButton {
            implicitWidth: 38
            implicitHeight: 38
            buttonRadius: Appearance.rounding.full
            enabled: !root.isDefault && !root.managed
            onClicked: root.defaultRequested()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: root.managed ? "auto_mode" : root.isDefault ? "check_circle" : "radio_button_unchecked"
                fill: root.isDefault ? 1 : 0
                iconSize: 22
                color: root.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: root.managed ? Translation.tr("EasyEffects decides this one")
                    : root.isDefault ? Translation.tr("Sound goes here")
                    : Translation.tr("Send sound here")
            }
        }
    }

    StyledSlider {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        configuration: StyledSlider.Configuration.S
        from: 0
        to: 1
        value: root.node?.audio?.volume ?? 0
        onMoved: {
            if (root.node?.audio)
                root.node.audio.volume = value;
        }
    }

    // A socket to pick only exists where the card has more than one, which is
    // where the choice is between the speakers and the headphone jack.
    StyledComboBox {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.ports.length > 1
        buttonIcon: "settings_input_component"
        model: root.ports.map(port => port.available
            ? port.description
            : `${port.description} — ${Translation.tr("not plugged in")}`)
        currentIndex: root.ports.findIndex(port => port.name === AudioRouting.activePortFor(root.node))
        onActivated: index => AudioRouting.setPort(root.node, root.ports[index].name)
    }
}
