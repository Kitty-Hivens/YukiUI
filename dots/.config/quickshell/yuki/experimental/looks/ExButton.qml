import QtQuick
import QtQuick.Controls

AbstractButton {
    id: root

    /** "accent", "tonal", "control" or "flat". */
    property string kind: "control"
    property string glyph: ""
    property string previewState: ""

    /** A right click, which the button itself never takes. */
    signal rightClicked

    readonly property color fill: kind === "accent" ? ExLooks.colors.accent
        : kind === "tonal" ? ExLooks.colors.tonal
        : kind === "control" ? ExLooks.colors.control
        : "transparent"
    readonly property color ink: kind === "accent" ? ExLooks.colors.accentInk
        : kind === "tonal" ? ExLooks.colors.tonalInk
        : kind === "flat" ? ExLooks.colors.accent
        : ExLooks.colors.controlInk

    hoverEnabled: true
    opacity: enabled ? 1 : ExLooks.colors.disabledOpacity
    implicitHeight: ExLooks.sizes.control
    implicitWidth: text.length > 0 ? row.implicitWidth + 2 * ExLooks.sizes.buttonPadding : implicitHeight

    background: Rectangle {
        radius: ExLooks.radius.control
        color: root.fill

        ExStateLayer {
            ink: root.ink
            hovered: root.hovered
            pressed: root.down
            previewState: root.previewState
        }
    }

    ExPrimaryOnly {
        z: 1
        onRightClicked: root.rightClicked()
    }

    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: ExLooks.spacing.s

            ExGlyph {
                visible: root.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root.ink
                size: 18
            }
            ExText {
                visible: root.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                role: "label"
                color: root.ink
            }
        }
    }
}
