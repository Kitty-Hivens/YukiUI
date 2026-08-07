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

    /// Small type for readings and labels, set in the configured monospace face.
    readonly property string readoutFamily: Config.options.appearance.fonts.monospace
    readonly property int readoutSize: 10
    readonly property real readoutSpacing: 0.8

    /// Headings are set in caps and spaced out, the way panel labels are.
    readonly property real headingSpacing: 1.4

    /// Length of the corner marks that stand in for a full border.
    readonly property int cornerLength: 10
    readonly property int cornerWeight: 1

    readonly property color cornerColor: ColorUtils.transparentize(Looks.colors.fg, 0.55)
    readonly property color rule: ColorUtils.transparentize(Looks.colors.fg, 0.88)
    readonly property color readoutColor: ColorUtils.transparentize(Looks.colors.fg, 0.45)
}
