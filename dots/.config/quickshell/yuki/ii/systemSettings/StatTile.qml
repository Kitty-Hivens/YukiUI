pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One live figure: what it measures, what it reads now, and where it has been.
 *
 * A figure with history is drawn as one, since the shape of the last minute
 * answers "is this normal" in a way a single number cannot. Everything else
 * falls back to a level, which occupies the same block so a row of tiles still
 * reads as one row.
 */
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string value: ""
    property string detail: ""
    property real fraction: 0
    property list<real> history: []

    // Near the ceiling is exactly the reading someone opened this page to find,
    // so it stops being drawn in the same colour as everything else.
    readonly property bool strained: root.fraction >= 0.9
    readonly property color accent: root.strained ? Appearance.colors.colError : Appearance.colors.colPrimary

    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    radius: Appearance.rounding.normal
    implicitWidth: 200
    implicitHeight: tileColumn.implicitHeight + tileColumn.anchors.margins * 2

    ColumnLayout {
        id: tileColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: root.value
            elide: Text.ElideRight
            font.pixelSize: 30
            font.variableAxes: ({
                "wght": 600
            })
            color: root.strained ? Appearance.colors.colError : Appearance.colors.colOnLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.detail.length > 0
            text: root.detail
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            id: well
            Layout.fillWidth: true
            Layout.topMargin: 10
            implicitHeight: 42
            radius: Appearance.rounding.verysmall
            color: ColorUtils.transparentize(root.accent, 0.92)

            // Both the graph's fill and the level run to the edge of the well,
            // so they are masked to its shape rather than clipped to its box,
            // which would square the corners they sit in.
            Item {
                id: wellContent
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wellContent.width
                        height: wellContent.height
                        radius: well.radius
                    }
                }

                Graph {
                    anchors.fill: parent
                    visible: root.history.length > 1
                    values: root.history
                    color: root.accent
                    fillOpacity: 0.32
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    visible: root.history.length <= 1
                    width: parent.width * Math.max(0, Math.min(1, root.fraction))
                    color: ColorUtils.transparentize(root.accent, 0.62)

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
