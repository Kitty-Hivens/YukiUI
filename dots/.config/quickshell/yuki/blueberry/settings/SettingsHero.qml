import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// The one switch a page is about, Bluetooth or Wi-Fi: how it stands, said
// large, beside its glyph on a disc that is the accent while on, and the
// switch. Only the switch switches: the plate holds the page's state, and a
// stray click on it turning the radio off would drop whatever was playing.
Rectangle {
    id: root

    property string glyph: ""
    /** How it stands, as the page's headline: "On, 1 connected" or "Off". */
    property string text: ""
    property string subtitle: ""
    /** How it stands, as the system says. */
    property bool on: false

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
        ExSwitch {
            checked: root.on
            enabled: root.enabled
            onToggled: {
                const wanted = checked;
                // Back to showing the system, which moves once it has.
                checked = Qt.binding(() => root.on);
                root.switched(wanted);
            }
        }
    }
}
