pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything pavucontrol is kept around for: devices and their volume, which
 * device new sound goes to, what each application is playing and where, the
 * socket a card drives, and the profile the card runs in.
 *
 * Volumes, mutes and the device list come from the PipeWire binding, which
 * reports them live. Profiles, ports and moving a stream go through
 * [AudioRouting], since the binding does not carry them.
 */
Item {
    id: root

    readonly property list<var> outputStreams: Audio.outputAppNodes
    readonly property list<var> inputStreams: Audio.inputAppNodes

    // Cards, ports and stream targets are only read while they are on screen.
    Component.onCompleted: AudioRouting.subscribers++
    Component.onDestruction: AudioRouting.subscribers--

    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 4
        font.pixelSize: Appearance.font.pixelSize.smallie
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    component Empty: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: Math.max(20, (pageFlick.width - width) / 2)
            // Narrower than the overview: a volume slider stretched across a
            // wide window is a long throw for a small adjustment.
            width: Math.min(pageFlick.width - 40, 880)
            spacing: 16

            Heading {
                text: Translation.tr("Output")
            }

            SystemCard {
                Layout.fillWidth: true

                Repeater {
                    model: Audio.outputDevices

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: parent.index > 0
                        }
                        AudioDeviceRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                            isDefault: parent.modelData.id === Pipewire.defaultAudioSink?.id
                            onDefaultRequested: Audio.setDefaultSink(parent.modelData)
                        }
                    }
                }
            }

            Heading {
                text: Translation.tr("Input")
            }

            SystemCard {
                Layout.fillWidth: true

                Repeater {
                    model: Audio.inputDevices

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: parent.index > 0
                        }
                        AudioDeviceRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                            isDefault: parent.modelData.id === Pipewire.defaultAudioSource?.id
                            onDefaultRequested: Audio.setDefaultSource(parent.modelData)
                        }
                    }
                }
            }

            Heading {
                text: Translation.tr("Playing")
            }

            SystemCard {
                Layout.fillWidth: true

                Empty {
                    visible: root.outputStreams.length === 0
                    text: Translation.tr("Nothing is playing")
                }

                Repeater {
                    model: root.outputStreams

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: parent.index > 0
                        }
                        AudioStreamRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                        }
                    }
                }
            }

            Heading {
                text: Translation.tr("Recording")
            }

            SystemCard {
                Layout.fillWidth: true

                Empty {
                    visible: root.inputStreams.length === 0
                    text: Translation.tr("Nothing is recording")
                }

                Repeater {
                    model: root.inputStreams

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: parent.index > 0
                        }
                        AudioStreamRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                        }
                    }
                }
            }

            Heading {
                text: Translation.tr("Hardware")
            }

            SystemCard {
                Layout.fillWidth: true

                Empty {
                    visible: AudioRouting.cards.length === 0
                    text: Translation.tr("No sound cards were found")
                }

                Repeater {
                    model: AudioRouting.cards

                    delegate: ColumnLayout {
                        id: cardEntry
                        required property var modelData
                        required property int index
                        readonly property var profiles: cardEntry.modelData.profiles
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: cardEntry.index > 0
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: cardEntry.modelData.description
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            // The whole point of a profile is which inputs and
                            // outputs a card offers, so name the card it is on.
                            text: cardEntry.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                        StyledComboBox {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            buttonIcon: "tune"
                            model: cardEntry.profiles.map(profile => profile.available
                                ? profile.description
                                : `${profile.description} — ${Translation.tr("not plugged in")}`)
                            currentIndex: cardEntry.profiles.findIndex(profile => profile.name === cardEntry.modelData.activeProfile)
                            onActivated: index => AudioRouting.setCardProfile(cardEntry.modelData.name, cardEntry.profiles[index].name)
                        }
                    }
                }
            }
        }
    }
}
