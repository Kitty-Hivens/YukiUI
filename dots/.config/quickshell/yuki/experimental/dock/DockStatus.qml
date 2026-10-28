import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.input
import qs.experimental.looks

// The keyboard layout, who is capturing, connection, sound, battery and the
// clock, at the far end of the dock, as buttons: the layout opens the list of
// layouts, the capture marks the list of who is capturing what, the icons open
// quick settings, the clock the notifications and the calendar, the way the
// Windows corner is divided.
Item {
    id: root

    property bool vertical: false
    /**
     * How thick the dock is across. The zones are drawn their own size but
     * take clicks across all of it, as the buttons of a Windows taskbar do:
     * a click near the dock's edge, above the icons, used to land on nothing.
     */
    property real crossSize: 0

    /** The icons were clicked. */
    signal clicked
    /** The clock was clicked. */
    signal clockClicked
    /** The layout was clicked. */
    signal layoutClicked
    /** The marks of who is capturing were clicked. */
    signal captureClicked

    /** The layouts, as the dock names them. */
    property ExLayouts layouts: ExLayouts {}

    /** What quick settings opens from. */
    readonly property Item statusButton: statusZone
    /** What the notifications open from. */
    readonly property Item clockButton: clockZone
    /** What the list of layouts opens from. */
    readonly property Item layoutButton: layoutZone
    /** What the list of who is capturing opens from. */
    readonly property Item captureButton: captureZone

    // A touchpad sends a notch in small pieces, which are added up to one.
    property real wheelRest: 0

    function turnVolume(delta: real) {
        if (!Audio.sink?.audio)
            return;
        root.wheelRest += delta;
        while (Math.abs(root.wheelRest) >= 120) {
            if (root.wheelRest > 0) {
                Audio.incrementVolume();
                root.wheelRest -= 120;
            } else {
                Audio.decrementVolume();
                root.wheelRest += 120;
            }
        }
    }

    readonly property bool showSeconds: Config.options.experimental.dock.clockSeconds
    // Ticking every second only while seconds are asked for.
    SystemClock {
        id: secondsClock
        enabled: root.showSeconds
        precision: SystemClock.Seconds
    }
    /** The shell's format of the time, with seconds after the minutes when asked. */
    readonly property string timeFormat: {
        const format = Config.options?.time.format ?? "hh:mm";
        return !root.showSeconds || format.includes("ss") ? format : format.replace("mm", "mm:ss");
    }
    /** The time as the dock shows it. */
    readonly property string time: root.showSeconds ? Qt.locale().toString(secondsClock.date, root.timeFormat) : DateTime.time

    /** The time at an hour of a day, for how wide the clock can get. */
    function sampleTime(hour: int): string {
        return Qt.locale().toString(new Date(2000, 0, 1, hour, 0, 0), root.timeFormat);
    }

    /** The time and what follows it, "pm" say, apart. */
    readonly property var clockParts: {
        const at = root.time.indexOf(" ");
        return at < 0 ? [root.time, ""] : [root.time.slice(0, at), root.time.slice(at + 1)];
    }

    implicitWidth: zones.implicitWidth
    implicitHeight: zones.implicitHeight

    component Zone: Item {
        id: zone

        default property alias content: holder.data
        /** Carries the dot that says something is waiting. */
        property bool marked: false
        /**
         * Room either side of the content, along the dock. Little enough that
         * the icons of two zones side by side stand as far apart as those
         * within one: with room for the hover plate the dock looked broken
         * into groups.
         */
        property real inset: root.vertical ? 6 : 4
        /** How far the hover plate reaches past that room, for space round what it lights. */
        readonly property real overhang: root.vertical ? 0 : Math.max(0, 8 - zone.inset)
        /**
         * How far its clicks reach past it on either side, across the dock,
         * to the dock's edges. Each zone's own: counted from the tallest of
         * them, the clock with its date, the status icons below it reached
         * short of the edges, and a click near the top of the dock missed them.
         */
        readonly property real reach: Math.max(0, (root.crossSize - (root.vertical ? zone.width : zone.height)) / 2)
        signal activated
        /** The wheel turned over the zone, in eighths of a degree. */
        signal wheeled(real delta)

        implicitWidth: holder.childrenRect.width + 2 * (root.vertical ? 6 : zone.inset)
        implicitHeight: holder.childrenRect.height + (root.vertical ? 16 : 12)
        // Down a vertical dock each zone sits in the middle of it.
        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter

        MouseArea {
            id: mouse
            anchors.fill: parent
            anchors.topMargin: root.vertical ? 0 : -zone.reach
            anchors.bottomMargin: root.vertical ? 0 : -zone.reach
            anchors.leftMargin: root.vertical ? -zone.reach : 0
            anchors.rightMargin: root.vertical ? -zone.reach : 0
            hoverEnabled: true
            onClicked: zone.activated()
            onWheel: event => zone.wheeled(event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x)
        }

        // Over the neighbour's room, which is fine: only one is ever lit.
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -zone.overhang
            anchors.rightMargin: -zone.overhang
            radius: ExLooks.radius.control
            color: "transparent"

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: mouse.containsMouse
                pressed: mouse.pressed
            }
        }

        Item {
            id: holder
            anchors.centerIn: parent
            width: childrenRect.width
            height: childrenRect.height
        }

        Rectangle {
            visible: zone.marked
            x: zone.width - width - 3
            y: 3
            width: 8
            height: 8
            radius: 4
            color: ExLooks.colors.accent
            border.width: 1.5
            border.color: ExLooks.colors.surface
        }
    }

    GridLayout {
        id: zones

        columns: root.vertical ? 1 : 4
        rowSpacing: 2
        columnSpacing: 2

        // Only when there is more than one layout to switch between.
        Zone {
            id: layoutZone

            visible: root.layouts.codes.length > 1
            onActivated: root.layoutClicked()

            // As wide as the widest of the layouts in use, whichever is shown,
            // so switching layouts does not shift the dock.
            ExText {
                id: layoutLabel
                width: widest.implicitWidth
                horizontalAlignment: Text.AlignHCenter
                text: root.layouts.short(root.layouts.codes[root.layouts.current] ?? HyprlandXkb.currentLayoutCode)
                // Quieter than the clock, to sit with the thin icons beside it.
                role: "caption"
                font.letterSpacing: 0.4

                Column {
                    id: widest
                    visible: false

                    Repeater {
                        model: root.layouts.codes

                        ExText {
                            required property string modelData
                            text: root.layouts.short(modelData)
                            role: "caption"
                            font.letterSpacing: 0.4
                        }
                    }
                }
            }
        }

        // Who is capturing, while anyone is: the screen recording the shell
        // started, a red mark, and the programs taking the screen, a camera,
        // a microphone or the sound playing, each by its own mark.
        Zone {
            id: captureZone

            readonly property var kinds: CaptureWatch.users.map(user => user.kind)

            visible: CaptureWatch.recording || CaptureWatch.users.length > 0
            onActivated: root.captureClicked()

            // In the font of the icons beside them, each as wide as its ink, so
            // they keep the same gaps as those icons.
            GridLayout {
                columns: root.vertical ? 1 : 5
                rowSpacing: 6
                columnSpacing: 10

                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: CaptureWatch.recording
                    name: "record_circle"
                    variants: [name]
                    size: 16
                    color: ExLooks.colors.destructive
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: captureZone.kinds.includes("screen")
                    name: "monitor_share"
                    variants: [name]
                    size: 18
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: captureZone.kinds.includes("camera")
                    name: "video"
                    variants: [name]
                    size: 18
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: captureZone.kinds.includes("microphone")
                    name: "microphone"
                    variants: [name]
                    size: 18
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: captureZone.kinds.includes("sound")
                    name: "waveform"
                    variants: [name]
                    size: 18
                }
            }
        }

        Zone {
            id: statusZone

            onActivated: root.clicked()
            // The wheel over the icons turns the sound, as it does over the
            // Windows ones.
            onWheeled: delta => root.turnVolume(delta)

            GridLayout {
                columns: root.vertical ? 1 : 3
                rowSpacing: 6
                columnSpacing: 10

                // As wide as the ink of their widest glyphs, so the gaps
                // between them are even.
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    name: ExStatusGlyphs.networkGlyph
                    variants: ExStatusGlyphs.networkGlyphs
                    badge: ExStatusGlyphs.networkBadge
                    pulse: ExStatusGlyphs.connecting === "bluetooth"
                    plate: ExLooks.colors.dockPlate
                    size: 18
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    name: ExStatusGlyphs.volumeGlyph
                    variants: ExStatusGlyphs.volumeVariants
                    ghost: name === "volume_low" || name === "volume_medium" ? "volume_high" : ""
                    size: 18
                }
                ExStatusGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: Battery.available
                    name: ExStatusGlyphs.batteryGlyph
                    variants: Battery.isCharging ? ExStatusGlyphs.chargingGlyphs : ExStatusGlyphs.dischargingGlyphs
                    color: Battery.isLowAndNotCharging ? ExLooks.colors.destructive : ExLooks.colors.text
                    size: 18
                }
            }
        }

        Zone {
            id: clockZone

            // Set off from the icons, as the Windows clock is.
            inset: 8
            // Notifications that arrived and have not been looked at.
            marked: Notifications.unread > 0
            onActivated: root.clockClicked()

            // Across the dock, the time over the date. Down a vertical dock
            // there is no room for either at length, so the time goes over
            // its am or pm, the way a Windows taskbar stood on its side does.
            ColumnLayout {
                spacing: 0

                // Its digits all of one width, and across the dock never
                // narrower than the widest time the format gives, an hour of
                // two digits in the morning or the evening: the font's own
                // digits differ, and everything before the clock moved a little
                // as the minutes turned.
                ExText {
                    id: timeLabel

                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignRight
                    Layout.minimumWidth: root.vertical ? 0 : Math.ceil(Math.max(morning.advanceWidth, evening.advanceWidth))
                    horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignRight
                    text: root.vertical ? root.clockParts[0] : root.time
                    role: "label"
                    font.features: ({ "tnum": 1 })
                    elide: Text.ElideNone

                    TextMetrics {
                        id: morning
                        font: timeLabel.font
                        text: root.sampleTime(10)
                    }
                    TextMetrics {
                        id: evening
                        font: timeLabel.font
                        text: root.sampleTime(22)
                    }
                }
                ExText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignRight
                    visible: text.length > 0
                    text: root.vertical ? root.clockParts[1] : (Config.options.experimental.dock.clockDate ? DateTime.shortDate : "")
                    role: "caption"
                    font.features: ({ "tnum": 1 })
                    dim: true
                    elide: Text.ElideNone
                }
            }
        }
    }
}
