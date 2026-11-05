import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// What a page is about, Bluetooth or the updates say: how it stands, said large,
// beside its glyph on a disc that is the accent while on, and at the far end the
// one switch or the buttons that change it. Only those act: the plate holds the
// page's state, and a stray click on it turning the radio off would drop
// whatever was playing.
Rectangle {
    id: root

    property string glyph: ""
    /** How it stands, as the page's headline: "On, 1 connected" or "Off". */
    property string text: ""
    property string subtitle: ""
    /** How it stands, as the system says. */
    property bool on: false
    /** A switch at the far end, for a page about one thing to turn on and off. */
    property bool switchable: true
    /** Buttons at the far end, before the switch if there is one. */
    default property alias actions: actionRow.data

    signal switched(bool wanted)

    readonly property var metrics: ExLooks.settings

    implicitHeight: row.implicitHeight + 2 * root.metrics.rowPadding
    radius: root.metrics.plateRadius
    color: root.metrics.plate

    RowLayout {
        id: row

        anchors.fill: parent
        anchors.margins: root.metrics.rowPadding
        spacing: root.metrics.rowPadding

        Rectangle {
            implicitWidth: root.metrics.heroChip
            implicitHeight: root.metrics.heroChip
            radius: width / 2
            color: root.on ? ExLooks.colors.accent : root.metrics.sunken

            Behavior on color {
                ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }

            ExGlyph {
                anchors.centerIn: parent
                text: root.glyph
                size: 24
                fill: root.on ? 1 : 0
                color: root.on ? ExLooks.colors.accentInk : ExLooks.colors.textDim
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            ExText {
                Layout.fillWidth: true
                text: root.text
                font.pixelSize: root.metrics.heading
                font.weight: ExLooks.font.weightTitle
            }
            ExText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                font.pixelSize: root.metrics.small
                dim: true
            }
        }
        Row {
            id: actionRow
            spacing: ExLooks.spacing.s
        }
        ExSystemSwitch {
            visible: root.switchable
            on: root.on
            enabled: root.enabled
            onSwitched: wanted => root.switched(wanted)
        }
    }
}
