pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

import qs.core.services
import qs.blueberry.looks

// Sound in quick settings, behind the arrow at the end of the volume, as on
// Windows 11: which device sound comes out of, and how loud each application
// plays. Unlike the other pages it is as tall as what it holds. Sockets, profiles and sending one application elsewhere are the
// settings' Sound page, which the button at the bottom opens.
ColumnLayout {
    id: root

    /** On screen. The names and icons of applications are worked out only while it is. */
    property bool shown: false

    readonly property var outputs: Audio.hardwareDevices(true)
    readonly property var playing: Audio.outputAppNodes

    signal back
    signal settingsRequested

    // Counted while on screen only: each costs a process.
    property bool counted: false
    onShownChanged: {
        if (root.shown === root.counted)
            return;
        root.counted = root.shown;
        StreamApps.subscribers += root.counted ? 1 : -1;
        AudioRouting.subscribers += root.counted ? 1 : -1;
    }
    Component.onDestruction: {
        if (root.counted) {
            StreamApps.subscribers--;
            AudioRouting.subscribers--;
        }
    }

    /**
     * What a device is, as Windows names it: what comes out of it, then
     * where it is. The names cards give themselves, a codec's or a chip's,
     * tell a person nothing, so what the active socket says comes first, and
     * the name is kept for a device that says nothing else about itself, as a
     * USB one in its pro profile has no sockets to say it with.
     */
    function describe(node): var {
        const props = node?.properties ?? {};
        const name = node?.name ?? "";
        const port = AudioRouting.activePortFor(node);
        const form = props["device.form-factor"] ?? "";
        const bus = name.startsWith("bluez_") ? "bluetooth" : (props["device.bus"] ?? "");
        const where = bus === "bluetooth" ? Translation.tr("Bluetooth")
            : bus === "usb" ? Translation.tr("USB")
            : form === "internal" || bus === "pci" ? Translation.tr("Built-in") : "";
        if (bus === "bluetooth")
            return { title: Audio.friendlyDeviceName(node), where: where, glyph: "headphones" };
        if (/hdmi|displayport|iec958/i.test(`${port} ${name}`))
            return { title: Translation.tr("HDMI"), where: Audio.friendlyDeviceName(node), glyph: "tv" };
        if (/headphone/i.test(port) || form === "headphone")
            return { title: Translation.tr("Headphones"), where: where, glyph: "headphones" };
        if (/headset/i.test(port) || form === "headset")
            return { title: Translation.tr("Headset"), where: where, glyph: "headset_mic" };
        if (/speaker/i.test(port) || form === "internal" || form === "speaker")
            return { title: Translation.tr("Speakers"), where: where, glyph: "speaker" };
        return { title: Audio.friendlyDeviceName(node), where: where, glyph: bus === "usb" ? "usb" : "speaker" };
    }

    // Without this the volume of an application is never delivered.
    PwObjectTracker {
        objects: root.shown ? [...root.outputs, ...root.playing] : []
    }

    spacing: ExLooks.spacing.s

    component SectionLabel: ExText {
        leftPadding: ExLooks.spacing.m
        topPadding: ExLooks.spacing.s
        bottomPadding: ExLooks.spacing.xs
        role: "caption"
        dim: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.xs

        ExButton {
            kind: "flat"
            glyph: "arrow_back"
            onClicked: root.back()
        }
        ExText {
            Layout.fillWidth: true
            Layout.leftMargin: ExLooks.spacing.xs
            text: Translation.tr("Sound")
            role: "title"
        }
    }

    // As tall as what it holds, up to a limit past which it scrolls: kept
    // at the height of the switches it was half empty.
    Flickable {
        id: scroller

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(lists.implicitHeight, 360)
        clip: true
        contentHeight: lists.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: lists

            width: scroller.width
            spacing: 2

            SectionLabel {
                topPadding: ExLooks.spacing.xs
                text: Translation.tr("Output")
            }

            // A device, picked by a click. Marked against the hardware the
            // default reaches, so a processor holding the default still marks
            // the device it plays out of.
            Repeater {
                model: root.outputs

                AbstractButton {
                    id: device

                    required property var modelData
                    readonly property bool inUse: device.modelData?.id === Audio.defaultSinkEndpoint?.id
                    readonly property var described: root.describe(device.modelData)
                    readonly property color ink: device.inUse ? ExLooks.colors.tonalInk : ExLooks.colors.text

                    ExPrimaryOnly {
                        z: 1
                    }

                    width: lists.width
                    implicitHeight: deviceRow.implicitHeight + 2 * ExLooks.spacing.s
                    hoverEnabled: true
                    onClicked: {
                        if (!device.inUse)
                            Audio.setDefaultSink(device.modelData);
                    }

                    // The one in use on a plate, as a switched on choice.
                    background: Rectangle {
                        radius: ExLooks.radius.control
                        color: device.inUse ? ExLooks.colors.tonal : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                        }

                        ExStateLayer {
                            ink: ExLooks.colors.text
                            hovered: device.hovered && !device.inUse
                            pressed: device.down && !device.inUse
                        }
                    }
                    contentItem: Item {
                        RowLayout {
                            id: deviceRow

                            x: ExLooks.spacing.m
                            y: ExLooks.spacing.s
                            width: parent.width - 2 * ExLooks.spacing.m
                            spacing: ExLooks.spacing.m

                            ExGlyph {
                                Layout.preferredWidth: 24
                                text: device.described.glyph
                                fill: device.inUse ? 1 : 0
                                color: device.ink
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                ExText {
                                    Layout.fillWidth: true
                                    text: device.described.title
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    role: "label"
                                    color: device.ink
                                }
                                ExText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: device.described.where
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    role: "caption"
                                    color: device.ink
                                    opacity: 0.8
                                }
                            }
                        }
                    }
                }
            }
            ExText {
                visible: root.outputs.length === 0
                leftPadding: ExLooks.spacing.m
                text: Translation.tr("Nothing to play through")
                dim: true
            }

            SectionLabel {
                text: Translation.tr("Applications")
            }

            // An application: muted by a click on its icon, and how loud.
            // Above a hundred for an application, not for a device: quiet
            // material is the application's problem, a card pushed past its
            // ceiling is how speakers start distorting.
            Repeater {
                model: root.playing

                Item {
                    id: app

                    required property var modelData
                    readonly property bool muted: app.modelData?.audio?.muted ?? false
                    readonly property string context: Audio.appNodeContext(app.modelData)

                    width: lists.width
                    implicitHeight: appColumn.implicitHeight + ExLooks.spacing.s

                    ColumnLayout {
                        id: appColumn

                        x: ExLooks.spacing.xs
                        width: parent.width - 2 * ExLooks.spacing.xs
                        spacing: 0

                        // In line with the slider under it.
                        ExText {
                            Layout.fillWidth: true
                            Layout.leftMargin: ExLooks.sizes.control + ExLooks.spacing.s
                            text: app.context.length > 0 ? `${Audio.appNodeDisplayName(app.modelData)}: ${app.context}` : Audio.appNodeDisplayName(app.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            role: "label"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ExLooks.spacing.s

                            ExButton {
                                kind: "flat"
                                onClicked: {
                                    if (app.modelData?.audio)
                                        app.modelData.audio.muted = !app.modelData.audio.muted;
                                }

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 22
                                    opacity: app.muted ? 0.35 : 1
                                    source: {
                                        const own = StreamApps.iconFor(app.modelData);
                                        if (AppSearch.iconExists(own))
                                            return Quickshell.iconPath(own, "image-missing");
                                        return Quickshell.iconPath(AppSearch.guessIcon(app.modelData?.properties["application.icon-name"] ?? app.modelData?.properties["node.name"] ?? ""), "image-missing");
                                    }
                                }
                            }
                            ExSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 1.5
                                value: app.modelData?.audio?.volume ?? 0
                                onMoved: {
                                    if (app.modelData?.audio)
                                        app.modelData.audio.volume = value;
                                }
                            }
                        }
                    }
                }
            }
            ExText {
                visible: root.playing.length === 0
                leftPadding: ExLooks.spacing.m
                text: Translation.tr("Nothing is playing")
                dim: true
            }
        }
    }

    ExButton {
        Layout.alignment: Qt.AlignLeft
        kind: "flat"
        text: Translation.tr("More sound settings")
        onClicked: root.settingsRequested()
    }
}
