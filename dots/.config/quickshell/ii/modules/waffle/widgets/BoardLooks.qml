pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

/**
 * The board's own vocabulary.
 *
 * Waffle is a copy of somebody else's shell and its Looks singleton holds that
 * copy's measurements. The widgets board is not a copy of anything, so the few
 * things that make it read as an instrument panel rather than a stack of tiles
 * live here instead of being smuggled into Looks.
 */
Singleton {
    id: root

    /// The board's unit of measure: the height of a line of its own text, the way
    /// Plasma sizes its grid. Everything below is a multiple of it, so the board
    /// follows the font and the scale factor instead of a set of pixel counts.
    readonly property real unit: boardMetrics.height
    readonly property int columnWidth: Math.round(root.unit * 22)
    /// The grid steps finer than a card is wide, so a card can stand between two
    /// columns as well as on one. A card is a whole number of segments across.
    readonly property int segments: 2
    readonly property int gutter: Math.round(root.unit)
    readonly property int padding: Math.round(root.unit * 1.5)
    readonly property int cardPadding: Math.round(root.unit)
    readonly property int controlSize: Math.round(root.unit * 1.6)
    /// The panel of widgets to choose from, which opens beside the board in a
    /// window of its own.
    readonly property int pickerWidth: root.columnWidth + root.padding * 2
    /// The margin a bar-attached panel keeps around itself.
    readonly property int visualMargin: 12

    function widthForColumns(columns) {
        return root.columnWidth * columns + root.gutter * (columns - 1) + root.padding * 2;
    }

    FontMetrics {
        id: boardMetrics
        font.family: Looks.font.family.ui
        font.pixelSize: Looks.font.pixelSize.normal
    }

    /// Small type for readings and labels, set in the configured monospace face.
    readonly property string readoutFamily: Config.options.appearance.fonts.monospace
    readonly property int readoutSize: Math.round(root.unit * 0.66)
    readonly property real readoutSpacing: 0.8

    /// Headings are set in caps and spaced out, the way panel labels are.
    readonly property real headingSpacing: 1.4

    /// Length of the corner marks that stand in for a full border.
    readonly property int cornerLength: Math.round(root.unit * 0.66)
    readonly property int cornerWeight: 1

    readonly property color cornerColor: ColorUtils.transparentize(Looks.colors.fg, 0.55)
    readonly property color rule: ColorUtils.transparentize(Looks.colors.fg, 0.88)
    readonly property color readoutColor: ColorUtils.transparentize(Looks.colors.fg, 0.45)
}
