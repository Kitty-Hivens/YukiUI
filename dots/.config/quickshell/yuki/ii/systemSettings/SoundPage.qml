pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.core.functions
import qs.ii.systemSettings
import qs.common.widgets
import qs.common

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




    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            PageHeading {
                text: Translation.tr("Output")
            }

            SystemCard {
                Layout.fillWidth: true

                // A card with an empty list in it is a box with nothing in it,
                // which reads as a page that has not finished loading rather than
                // as a machine with nothing to play through.
                PageNote {
                    visible: Audio.hardwareDevices(true).length === 0
                    text: Translation.tr("Nothing to play through")
                }

                Repeater {
                    model: Audio.hardwareDevices(true)

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: parent.index > 0
                        }
                        AudioDeviceRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                            // Against the hardware the default reaches, not
                            // against the default itself: a processor holding
                            // it still ends up playing out of one of these.
                            isDefault: parent.modelData.id === Audio.defaultSinkEndpoint?.id
                            onDefaultRequested: Audio.setDefaultSink(parent.modelData)
                        }
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Input")
            }

            SystemCard {
                Layout.fillWidth: true

                PageNote {
                    visible: Audio.hardwareDevices(false).length === 0
                    text: Translation.tr("Nothing to record from")
                }

                Repeater {
                    model: Audio.hardwareDevices(false)

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: parent.index > 0
                        }
                        AudioDeviceRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                            isDefault: parent.modelData.id === Audio.defaultSourceEndpoint?.id
                            onDefaultRequested: Audio.setDefaultSource(parent.modelData)
                        }
                    }
                }
            }

            PageHeading {
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

                        PageDivider {
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

            PageHeading {
                text: Translation.tr("Playing")
            }

            SystemCard {
                Layout.fillWidth: true

                PageNote {
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

                        PageDivider {
                            visible: parent.index > 0
                        }
                        AudioStreamRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                        }
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Recording")
            }

            SystemCard {
                Layout.fillWidth: true

                PageNote {
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

                        PageDivider {
                            visible: parent.index > 0
                        }
                        AudioStreamRow {
                            Layout.fillWidth: true
                            node: parent.modelData
                        }
                    }
                }
            }

            PageHeading {
                text: Translation.tr("System sounds")
            }

            // The shell's own noises, as opposed to what the machine can play:
            // which theme they come from, and which of them are made at all.
            SystemCard {
                Layout.fillWidth: true

                ContentSubsection {
                    title: Translation.tr("Theme")
                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.sounds.theme
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.sounds.theme = text
                    }
                }

                ConfigSwitch {
                    id: batterySound
                    text: Translation.tr("Battery")
                    buttonIcon: "battery_android_full"
                    Binding {
                        target: batterySound
                        property: "checked"
                        value: Config.options.sounds.battery
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== Config.options.sounds.battery)
                            Config.options.sounds.battery = checked;
                    }
                }
                ConfigSwitch {
                    id: pomodoroSound
                    text: Translation.tr("Pomodoro")
                    buttonIcon: "av_timer"
                    Binding {
                        target: pomodoroSound
                        property: "checked"
                        value: Config.options.sounds.pomodoro
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== Config.options.sounds.pomodoro)
                            Config.options.sounds.pomodoro = checked;
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Hardware")
            }

            SystemCard {
                Layout.fillWidth: true

                PageNote {
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

                        PageDivider {
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
                            id: profileSelector
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            buttonIcon: "tune"
                            model: cardEntry.profiles.map(profile => profile.available
                                ? profile.description
                                : `${profile.description} — ${Translation.tr("not plugged in")}`)
                            currentIndex: cardEntry.profiles.findIndex(profile => profile.name === cardEntry.modelData.activeProfile)
                            onActivated: index => {
                                AudioRouting.setCardProfile(cardEntry.modelData.name, cardEntry.profiles[index].name);
                                // The box writes its own index on a choice, which
                                // drops the binding above and leaves it showing the
                                // profile asked for rather than the one in force.
                                profileSelector.currentIndex = Qt.binding(() => cardEntry.profiles.findIndex(profile => profile.name === cardEntry.modelData.activeProfile));
                            }
                        }
                    }
                }
            }
        }
    }
}
