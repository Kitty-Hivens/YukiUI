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
    readonly property list<var> processors: Audio.virtualDevices(true).concat(Audio.virtualDevices(false))

    // Cards, ports and the name behind a stream's process are only read while
    // they are on screen.
    Component.onCompleted: {
        AudioRouting.subscribers++;
        StreamApps.subscribers++;
    }
    Component.onDestruction: {
        AudioRouting.subscribers--;
        StreamApps.subscribers--;
    }

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
                    model: Audio.hardwareDevices(true)

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
                    model: Audio.hardwareDevices(false)

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
                visible: root.processors.length > 0
                text: Translation.tr("Processing")
            }

            // Not devices and not listed among them: these answer "through
            // what", which is a different question from "out of what".
            SystemCard {
                Layout.fillWidth: true
                visible: root.processors.length > 0

                Repeater {
                    model: root.processors

                    delegate: ColumnLayout {
                        id: processorEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        Divider {
                            visible: processorEntry.index > 0
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            MaterialSymbol {
                                text: "graphic_eq"
                                iconSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.colors.colSubtext
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Audio.friendlyDeviceName(processorEntry.modelData)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Audio.managedByProcessor(processorEntry.modelData)
                                        ? Translation.tr("Applications play through it, and its own level changes nothing")
                                        : Translation.tr("Created by a program rather than by hardware")
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    // Where it hands the sound on, followed
                                    // through the graph rather than assumed
                                    // from whatever the default device is.
                                    readonly property var endpoint: Audio.endpointOf(processorEntry.modelData)
                                    visible: endpoint !== null
                                    // Names the control that changes it, since
                                    // this line is not one: the processor
                                    // follows whatever plays sound by default.
                                    text: `${Translation.tr("Plays into %1").arg(Audio.friendlyDeviceName(endpoint))} · ${Translation.tr("follows the device chosen above")}`
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
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
