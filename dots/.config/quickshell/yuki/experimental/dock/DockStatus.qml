import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.services
import qs.experimental.input
import qs.experimental.looks

// The keyboard layout, connection, sound, battery and the clock, at the far end
// of the dock, as buttons: the layout opens the list of layouts, the icons open
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
    readonly property real reach: Math.max(0, (root.crossSize - (root.vertical ? zones.implicitWidth : zones.implicitHeight)) / 2)

    /** The icons were clicked. */
    signal clicked
    /** The clock was clicked. */
    signal clockClicked
    /** The layout was clicked. */
    signal layoutClicked

    /** The layouts, as the dock names them. */
    property ExLayouts layouts: ExLayouts {}

    /** What quick settings opens from. */
    readonly property Item statusButton: statusZone
    /** What the notifications open from. */
    readonly property Item clockButton: clockZone
    /** What the list of layouts opens from. */
    readonly property Item layoutButton: layoutZone

    readonly property string batteryGlyph: {
        if (Battery.isCharging)
            return "battery_charging_full";
        if (Battery.percentage >= 0.95)
            return "battery_full";
        return `battery_${Math.max(0, Math.min(6, Math.round(Battery.percentage * 6)))}_bar`;
    }
    readonly property string volumeGlyph: {
        if (Audio.sink?.audio?.muted ?? false)
            return "volume_off";
        return Audio.value > 0.5 ? "volume_up" : (Audio.value > 0 ? "volume_down" : "volume_mute");
    }

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
    /** The time as the dock shows it: the shell's format, with seconds after the minutes when asked. */
    readonly property string time: {
        if (!root.showSeconds)
            return DateTime.time;
        const format = Config.options?.time.format ?? "hh:mm";
        return Qt.locale().toString(secondsClock.date, format.includes("ss") ? format : format.replace("mm", "mm:ss"));
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
        /** Room either side of the content, along the dock. */
        property real inset: root.vertical ? 6 : 10
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
            anchors.topMargin: root.vertical ? 0 : -root.reach
            anchors.bottomMargin: root.vertical ? 0 : -root.reach
            anchors.leftMargin: root.vertical ? -root.reach : 0
            anchors.rightMargin: root.vertical ? -root.reach : 0
            hoverEnabled: true
            onClicked: zone.activated()
            onWheel: event => zone.wheeled(event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x)
        }

        Rectangle {
            anchors.fill: parent
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

        columns: root.vertical ? 1 : 3
        rowSpacing: 2
        columnSpacing: 2

        // Only when there is more than one layout to switch between.
        Zone {
            id: layoutZone

            visible: root.layouts.codes.length > 1
            // Close to its letters, as the icons beside it are to theirs.
            inset: 6
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

                ExGlyph {
                    Layout.alignment: Qt.AlignCenter
                    text: Network.materialSymbol
                    size: 18
                }
                ExGlyph {
                    Layout.alignment: Qt.AlignCenter
                    text: root.volumeGlyph
                    size: 18
                }
                ExGlyph {
                    Layout.alignment: Qt.AlignCenter
                    visible: Battery.available
                    text: root.batteryGlyph
                    size: 18
                }
            }
        }

        Zone {
            id: clockZone

            // Notifications that arrived and have not been looked at.
            marked: Notifications.unread > 0
            onActivated: root.clockClicked()

            // Across the dock, the time over the date. Down a vertical dock
            // there is no room for either at length, so the time goes over
            // its am or pm, the way a Windows taskbar stood on its side does.
            ColumnLayout {
                spacing: 0

                ExText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignRight
                    text: root.vertical ? root.clockParts[0] : root.time
                    role: "label"
                    elide: Text.ElideNone
                }
                ExText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignRight
                    visible: text.length > 0
                    text: root.vertical ? root.clockParts[1] : (Config.options.experimental.dock.clockDate ? DateTime.shortDate : "")
                    role: "caption"
                    dim: true
                    elide: Text.ElideNone
                }
            }
        }
    }
}
