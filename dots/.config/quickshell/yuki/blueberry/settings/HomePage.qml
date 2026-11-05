pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.UPower

import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// Where the settings open: this machine, and how its parts stand now, a card
// each. A card's top leads to its page; under it is the one thing worth
// changing from here, a switch or a level, always on the same line.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var metrics: ExLooks.settings
    readonly property int columns: root.width >= 720 ? 3 : 2
    readonly property var screenBrightness: Brightness.monitors[0] ?? null
    readonly property bool updatesPending: Updates.available && Updates.count > 0

    /** "12,3 GB", in the units a disk is sold in and the shell's own numbers. */
    function bytes(value: real): string {
        const units = [Translation.tr("B"), Translation.tr("KB"), Translation.tr("MB"), Translation.tr("GB"), Translation.tr("TB")];
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000;
            unit++;
        }
        const digits = value >= 100 || unit === 0 ? 0 : 1;
        return `${Number(value).toLocaleString(Qt.locale(Translation.languageCode), "f", digits)} ${units[unit]}`;
    }

    /** The disks the system and the home folder are on, each once: { target, size, used }. */
    property var disks: []
    property string kernel: ""

    Process {
        running: true
        // Told apart by the device, not by where it is mounted: a home on a
        // subvolume of the system's disk is the same disk twice.
        command: ["df", "-B1", "--output=source,size,used,target", "/", Directories.home.replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                root.disks = text.trim().split("\n").slice(1).map(line => line.trim().split(/\s+/))
                    .filter(fields => fields.length >= 4 && !seen.has(fields[0]) && seen.add(fields[0]))
                    .map(fields => ({ size: Number(fields[1]), used: Number(fields[2]), target: fields.slice(3).join(" ") }));
            }
        }
    }
    Process {
        running: true
        command: ["uname", "-r"]
        stdout: StdioCollector {
            onStreamFinished: root.kernel = text.trim()
        }
    }

    spacing: root.metrics.groupGap

    // The machine, over its wallpaper, and what wants a hand in its corner.
    // Rounded by corners of the pane's own tone laid over the picture rather
    // than by clipping, which takes a shader: drawn without one, the clipped
    // picture did not draw at all.
    Rectangle {
        id: hero

        Layout.fillWidth: true
        // Grows with the window, so the picture keeps its shape on a wide one.
        implicitHeight: Math.round(Math.max(168, Math.min(280, hero.width * 0.16)))
        color: root.metrics.sunken

        Image {
            anchors.fill: parent
            source: Config.options.background.wallpaperPath
            sourceSize: Qt.size(2560, 560)
            fillMode: Image.PreserveAspectCrop
            // Decoded with the page, which is built away from the screen
            // anyway, so the picture is there when the page is.
            asynchronous: false
        }
        // Dark where the text and the buttons stand, so they read over any
        // picture: from the left edge, and along the bottom.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#a6000000" }
                GradientStop { position: 0.6; color: "#26000000" }
                GradientStop { position: 1; color: "#00000000" }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#00000000" }
                GradientStop { position: 1; color: "#66000000" }
            }
        }
        ColumnLayout {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: root.metrics.rowPadding + ExLooks.spacing.s
            spacing: 2

            ExText {
                text: SystemInfo.hostname
                font.pixelSize: root.metrics.display
                font.weight: ExLooks.font.weightTitle
                color: ExLooks.colors.scrimInk
            }
            ExText {
                text: `${SystemInfo.distroName}  ·  ${root.settings?.username ?? ""}`
                font.pixelSize: root.metrics.body
                color: ExLooks.colors.scrimInk
                opacity: 0.85
            }
        }
        RowLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.metrics.rowPadding + ExLooks.spacing.s
            spacing: ExLooks.spacing.s

            // Updates, said quietly where the eye is not first drawn.
            GlassPill {
                visible: root.updatesPending
                glyph: "system_update_alt"
                text: Translation.tr("%1 updates").arg(Updates.count)
                onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.update])
            }
            GlassPill {
                glyph: "wallpaper"
                text: Translation.tr("Background")
                leads: true
                onClicked: root.settings.open("background")
            }
        }

        Repeater {
            model: 4

            Shape {
                id: cap

                required property int index
                readonly property real r: root.metrics.plateRadius

                // Each corner: the square a quarter circle leaves outside itself.
                x: cap.index % 2 === 0 ? 0 : hero.width - cap.r
                y: cap.index < 2 ? 0 : hero.height - cap.r
                width: cap.r
                height: cap.r
                rotation: [0, 90, 270, 180][cap.index]

                ShapePath {
                    strokeWidth: -1
                    fillColor: root.metrics.pane
                    startX: 0
                    startY: 0
                    PathLine { x: cap.r; y: 0 }
                    PathArc { x: 0; y: cap.r; radiusX: cap.r; radiusY: cap.r; direction: PathArc.Counterclockwise }
                    PathLine { x: 0; y: 0 }
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: root.columns
        columnSpacing: ExLooks.spacing.m
        rowSpacing: ExLooks.spacing.m

        HomeCard {
            glyph: ExQuickTiles.info("wifi").glyph
            hue: 195
            title: Translation.tr("Wi-Fi")
            subtitle: ExQuickTiles.info("wifi").subtitle
            page: "wifi"

            Meter {
                Layout.fillWidth: true
                visible: !!Network.active
                value: (Network.active?.strength ?? 0) / 100
            }
            ExText {
                visible: !!Network.active
                text: {
                    const frequency = Network.active?.frequency ?? 0;
                    return frequency >= 5900 ? "6 GHz" : frequency >= 5000 ? "5 GHz" : frequency > 0 ? "2.4 GHz" : "";
                }
                font.pixelSize: root.metrics.small
                dim: true
            }
            Item {
                visible: !Network.active
                Layout.fillWidth: true
            }
            ExSystemSwitch {
                on: Network.wifiEnabled
                onSwitched: wanted => Network.enableWifi(wanted)
            }
        }
        HomeCard {
            glyph: ExQuickTiles.info("bluetooth").glyph
            hue: 300
            title: Translation.tr("Bluetooth")
            subtitle: !BluetoothStatus.enabled ? Translation.tr("Off")
                : BluetoothStatus.activeDeviceCount > 0 ? Translation.tr("%1 connected").arg(BluetoothStatus.activeDeviceCount)
                : Translation.tr("Not connected")
            page: "bluetooth"

            ExText {
                Layout.fillWidth: true
                text: BluetoothStatus.firstActiveDevice?.name ?? ""
                font.pixelSize: root.metrics.small
                dim: true
            }
            ExText {
                visible: BluetoothStatus.firstActiveDevice?.batteryAvailable ?? false
                text: `${Math.round((BluetoothStatus.firstActiveDevice?.battery ?? 0) * 100)}%`
                font.pixelSize: root.metrics.small
                font.features: { "tnum": 1 }
                dim: true
            }
            ExSystemSwitch {
                enabled: BluetoothStatus.available
                on: BluetoothStatus.enabled
                onSwitched: wanted => {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = wanted;
                }
            }
        }
        HomeCard {
            glyph: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
            hue: 25
            title: Translation.tr("Sound")
            subtitle: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output")
            page: "sound"

            ExSlider {
                Layout.fillWidth: true
                implicitWidth: 0
                enabled: !!Audio.sink?.audio
                from: 0
                to: 1
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.volume = value;
                }
            }
            ExText {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%`
                font.pixelSize: root.metrics.small
                font.features: { "tnum": 1 }
                dim: true
            }
        }
        HomeCard {
            glyph: "brightness_medium"
            hue: 85
            title: Translation.tr("Display")
            subtitle: Hyprsunset.temperatureActive ? Translation.tr("Night light on") : Translation.tr("Night light off")
            page: "display"

            ExSlider {
                Layout.fillWidth: true
                implicitWidth: 0
                enabled: root.screenBrightness?.ready ?? false
                from: 0
                to: 1
                value: root.screenBrightness?.brightness ?? 0
                onMoved: root.screenBrightness?.setBrightness(value)
            }
            // Night light, its moon on a tinted plate while it is on.
            ExToolButton {
                implicitWidth: 28
                implicitHeight: 28
                glyph: "nightlight"
                toggled: Hyprsunset.temperatureActive
                onClicked: Hyprsunset.toggleTemperature(!Hyprsunset.temperatureActive)
            }
        }
        HomeCard {
            glyph: !Battery.available ? "power" : Battery.isCharging ? "battery_charging_full" : "battery_full"
            hue: 145
            title: Translation.tr("Power")
            subtitle: !Battery.available ? ExQuickTiles.powerProfileName
                : `${Math.round(Battery.percentage * 100)}%  ·  ${ExQuickTiles.powerProfileName}`
            page: "power"

            SegmentRow {
                Layout.fillWidth: true
                choices: [
                    { value: PowerProfile.PowerSaver, glyph: "energy_savings_leaf", text: "" },
                    { value: PowerProfile.Balanced, glyph: "balance", text: "" },
                    ...(PowerProfiles.hasPerformanceProfile ? [{ value: PowerProfile.Performance, glyph: "speed", text: "" }] : [])
                ]
                current: PowerProfiles.profile
                onPicked: value => PowerProfiles.profile = value
            }
        }
        HomeCard {
            glyph: "palette"
            hue: 350
            title: Translation.tr("Appearance")
            subtitle: ExLooks.dark ? Translation.tr("Dark") : Translation.tr("Light")
            page: "colors"

            SegmentRow {
                Layout.fillWidth: true
                choices: [
                    { value: "light", glyph: "light_mode", text: Translation.tr("Light") },
                    { value: "dark", glyph: "dark_mode", text: Translation.tr("Dark") }
                ]
                current: ExLooks.dark ? "dark" : "light"
                onPicked: value => {
                    if ((value === "dark") !== ExLooks.dark)
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", value, "--noswitch"]);
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("This computer")

        Repeater {
            model: root.disks

            SettingsCard {
                id: disk

                required property var modelData
                readonly property real share: disk.modelData.size > 0 ? disk.modelData.used / disk.modelData.size : 0

                glyph: "hard_drive"
                text: disk.modelData.target === "/" ? Translation.tr("System disk") : disk.modelData.target
                description: Translation.tr("%1 of %2 used").arg(root.bytes(disk.modelData.used)).arg(root.bytes(disk.modelData.size))

                Meter {
                    width: 140
                    value: disk.share
                    warn: disk.share > 0.9
                }
            }
        }
        SettingsCard {
            glyph: "system_update_alt"
            text: Translation.tr("Updates")
            description: Updates.checking ? Translation.tr("Checking...")
                : !Updates.available ? Translation.tr("Not checked yet")
                : Updates.count > 0 ? Translation.tr("%1 packages can be updated").arg(Updates.count)
                : Translation.tr("Everything is up to date")
        }
        SettingsCard {
            glyph: "memory"
            text: Translation.tr("Kernel")
            description: root.kernel
        }
    }

    // A part of the machine. Its top, the glyph in its own colour, the name
    // and how it stands, leads to its page and lights under the pointer; the
    // line under it holds what can be changed from here, at the same height
    // in every card.
    component HomeCard: Rectangle {
        id: card

        property string glyph
        property real hue: -1
        property string title
        property string subtitle
        property string page
        default property alias controls: controlRow.data
        readonly property int edge: (header.height - root.metrics.rowChip) / 2

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        // As much room under the controls as over the disc.
        implicitHeight: header.height + controlRow.height + card.edge
        radius: root.metrics.plateRadius
        color: root.metrics.plate

        AbstractButton {
            id: header

            ExPrimaryOnly {
                z: 1
            }

            width: parent.width
            height: 50
            hoverEnabled: true
            onClicked: root.settings.open(card.page)

            ExFocusRing {
                anchors.margins: 0
                cornerRadius: 4
            }

            background: Rectangle {
                topLeftRadius: root.metrics.plateRadius
                topRightRadius: root.metrics.plateRadius
                color: ExLooks.colors.text
                opacity: header.down ? ExLooks.colors.pressOpacity : header.hovered ? ExLooks.colors.hoverOpacity : 0

                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }
            }
            contentItem: RowLayout {
                spacing: ExLooks.spacing.m

                SettingsChip {
                    Layout.leftMargin: root.metrics.rowPadding
                    glyph: card.glyph
                    hue: card.hue
                    size: root.metrics.rowChip
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: card.title
                        font.pixelSize: root.metrics.body
                        font.weight: ExLooks.font.weightTitle
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: card.subtitle
                        font.pixelSize: root.metrics.small
                        dim: true
                    }
                }
                ExGlyph {
                    Layout.rightMargin: root.metrics.rowPadding - 4
                    text: "chevron_right"
                    size: 20
                    color: ExLooks.colors.textDim
                }
            }
        }
        RowLayout {
            id: controlRow

            x: root.metrics.rowPadding
            y: header.height
            width: parent.width - 2 * x
            height: 28
            spacing: ExLooks.spacing.s
        }
    }

    // How full something is, read only: thin and without a knob, so it is
    // not taken for a slider.
    component Meter: Rectangle {
        property real value: 0
        property bool warn: false

        implicitWidth: 120
        implicitHeight: 4
        radius: 2
        color: root.metrics.sunken

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: parent.warn ? ExLooks.colors.warning : ExLooks.colors.textDim
        }
    }

    // On the picture: a word with its glyph on a dark glass, so it reads on
    // anything; one that leads elsewhere ends in a chevron.
    component GlassPill: AbstractButton {
        id: pill

        ExPrimaryOnly {
            z: 1
        }

        property string glyph
        property bool leads: false

        hoverEnabled: true
        implicitHeight: 32
        implicitWidth: pillRow.implicitWidth + 2 * ExLooks.spacing.m

        ExFocusRing {
            cornerRadius: height / 2
        }

        background: Rectangle {
            radius: height / 2
            color: pill.hovered ? "#80000000" : "#59000000"
        }
        contentItem: Item {
            RowLayout {
                id: pillRow

                anchors.centerIn: parent
                spacing: ExLooks.spacing.xs

                ExGlyph {
                    text: pill.glyph
                    size: 16
                    color: ExLooks.colors.scrimInk
                }
                ExText {
                    text: pill.text
                    font.pixelSize: root.metrics.small
                    font.weight: ExLooks.font.weightTitle
                    color: ExLooks.colors.scrimInk
                }
                ExGlyph {
                    visible: pill.leads
                    text: "chevron_right"
                    size: 16
                    color: ExLooks.colors.scrimInk
                }
            }
        }
    }

    // A choice of a few, side by side and equal on a sunken track, the one
    // in force on a tinted plate.
    component SegmentRow: Rectangle {
        id: segments

        property var choices: []
        property var current

        signal picked(var value)

        implicitHeight: 28
        radius: height / 2
        color: root.metrics.sunken

        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 2

            Repeater {
                model: segments.choices

                AbstractButton {
                    id: segment

                    ExPrimaryOnly {
                        z: 1
                    }

                    required property var modelData
                    readonly property bool here: segment.modelData.value === segments.current

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    hoverEnabled: true
                    onClicked: segments.picked(segment.modelData.value)

                    ExFocusRing {
                        anchors.margins: 0
                        cornerRadius: height / 2 - 2
                    }

                    background: Rectangle {
                        radius: height / 2
                        color: segment.here ? ExLooks.colors.tonal : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: ExLooks.motion.fast }
                        }

                        ExStateLayer {
                            ink: ExLooks.colors.text
                            hovered: segment.hovered && !segment.here
                            pressed: segment.down
                        }
                    }
                    contentItem: RowLayout {
                        spacing: 4

                        Item {
                            Layout.fillWidth: true
                        }
                        ExGlyph {
                            text: segment.modelData.glyph
                            size: 16
                            fill: segment.here ? 1 : 0
                            color: segment.here ? ExLooks.colors.tonalInk : ExLooks.colors.textDim
                        }
                        ExText {
                            visible: segment.modelData.text.length > 0
                            text: segment.modelData.text
                            font.pixelSize: root.metrics.small
                            font.weight: segment.here ? ExLooks.font.weightTitle : ExLooks.font.weightBody
                            color: segment.here ? ExLooks.colors.tonalInk : ExLooks.colors.textDim
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
