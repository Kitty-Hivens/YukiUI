pragma Singleton

import QtQuick
import Quickshell

import qs.common
import qs.core

/**
 * Every measure and colour Blueberry's kit draws with.
 *
 * Grown out of the components rather than written ahead of them: a value
 * appears here once a component needs it, and not before.
 */
Singleton {
    id: root

    /**
     * Dark or light, as the rest of the system is: the one mode the toolkit
     * themes follow too, so the shell and the applications never disagree, and
     * icons an application draws for a dark panel are not lost on a light one.
     */
    readonly property bool dark: Appearance.m3colors.darkmode

    readonly property QtObject colors: QtObject {
        readonly property color background: root.dark ? "#1b1c21" : "#eef0f4"
        readonly property color surface: root.dark ? "#26272d" : "#ffffff"
        readonly property color surfaceSunken: root.dark ? "#1f2025" : "#f3f4f7"
        readonly property color text: root.dark ? "#e9eaf0" : "#15161a"
        readonly property color textDim: root.dark ? "#9a9daa" : "#686b76"
        readonly property color border: root.dark ? "#363840" : "#e4e6ec"
        readonly property color hairline: root.dark ? "#1fffffff" : "#0f000000"

        readonly property color accent: root.dark ? "#6179f2" : "#4f6bed"
        readonly property color accentInk: "#ffffff"
        /** The accent as text or a thin glyph, dark enough to read at small sizes on any surface. */
        readonly property color accentText: root.dark ? "#8c9cf8" : "#3f5bdc"
        readonly property color tonal: root.dark ? "#2d3456" : "#e7ebfd"
        readonly property color tonalInk: root.dark ? "#c6cffd" : "#2c45b8"
        /** A step darker than tonal, for what sits behind a tonal plate. */
        readonly property color tonalDeep: root.dark ? "#39416b" : "#d2d9fa"
        readonly property color control: root.dark ? "#34363e" : "#e2e5ec"
        readonly property color controlInk: root.dark ? "#e9eaf0" : "#15161a"
        readonly property color destructive: root.dark ? "#ff7b72" : "#c01c28"
        /** Between fine and too much: a reading running high. */
        readonly property color warning: root.dark ? "#f0b45a" : "#b86e00"

        /** Laid over a fill in the fill's own foreground colour. */
        readonly property real hoverOpacity: 0.06
        readonly property real pressOpacity: 0.12
        readonly property real disabledOpacity: 0.4

        readonly property color switchTrackOff: root.dark ? "#74778a" : "#8e919c"
        readonly property color knob: "#ffffff"
        /** A white knob on a light track needs an edge to exist at all. */
        readonly property color knobEdge: root.dark ? "#33000000" : "#1f000000"
        readonly property color sliderTrack: root.dark ? "#3c3e47" : "#dde1ea"

        readonly property color shadow: root.dark ? "#73000000" : "#2a1a2140"

        /** The dock's plate, as see-through as its settings ask. */
        readonly property color dockPlate: Qt.rgba(root.dark ? 0x24 / 255 : 1, root.dark ? 0x25 / 255 : 1, root.dark ? 0x2b / 255 : 1,
            Math.max(0, Math.min(100, Config.options?.blueberry?.dock?.opacity ?? 95)) / 100)
        /** Laid over the screen behind a dialog. */
        readonly property color scrim: root.dark ? "#80000000" : "#4d15161a"
        /** Heavier, for a screen that asks for a decision, like the session menu. */
        readonly property color scrimStrong: root.dark ? "#99000000" : "#5915161a"
        /** What is drawn on a scrim. */
        readonly property color scrimInk: "#ffffff"
        /** Over the blurred wallpaper of the lock screen. */
        readonly property color lockVeil: root.dark ? "#66101216" : "#66eef0f4"

        /**
         * A plane over a game, which the compositor blurs the game behind:
         * the surface, the controls on it and what is sunk into it let the
         * game's colour through. The compositor blurs only what is more
         * opaque than its threshold, which the glass is and the scrim under
         * it, with a shadow on top, is not.
         */
        readonly property color glass: root.dark ? "#b326272d" : "#b8ffffff"
        readonly property color glassControl: root.dark ? "#17ffffff" : "#14000000"
        readonly property color glassSunken: root.dark ? "#2e000000" : "#0d000000"
        /** The game behind the game bar, dimmed less than a screen under a dialog. */
        readonly property color scrimLight: root.dark ? "#40000000" : "#2615161a"
    }

    readonly property QtObject radius: QtObject {
        readonly property real control: 11
        readonly property real tile: 16
        readonly property real menu: 14
        readonly property real menuItem: 8
        /** A settings card: rounder than a menu row, squarer than a tile. */
        readonly property real card: 10
        readonly property real panel: 22
    }

    readonly property QtObject sizes: QtObject {
        readonly property real control: 36
        readonly property real buttonPadding: 16
        readonly property real icon: 20
        readonly property real switchWidth: 44
        readonly property real switchHeight: 24
        readonly property real knob: 18
        readonly property real knobPressedStretch: 6
        readonly property real sliderTrack: 6
        readonly property real sliderKnob: 18
        readonly property real tileHeight: 56
        readonly property real menuItem: 34
        readonly property real menuWidth: 240
        readonly property real menuPadding: 6
    }

    readonly property QtObject dock: QtObject {
        readonly property real thickness: 52
        readonly property real cell: 42
        readonly property real icon: 32
        readonly property real spacing: 2
        readonly property real launcherGlyph: 26
        /** A button standing for one window, its title beside the icon. */
        readonly property real labelledWidth: 176
        /** How far a floating dock stands off the screen edge. */
        readonly property real floatingGap: 8
        readonly property real floatingRadius: 18
    }

    readonly property QtObject spacing: QtObject {
        readonly property real xs: 4
        readonly property real s: 8
        readonly property real m: 12
        readonly property real l: 16
        readonly property real xl: 24
    }

    readonly property QtObject font: QtObject {
        readonly property string family: "Adwaita Sans"
        readonly property string glyphs: "Material Symbols Rounded"
        readonly property real body: 14
        readonly property real label: 13
        readonly property real caption: 12
        readonly property real title: 17
        readonly property int weightBody: 400
        readonly property int weightLabel: 500
        readonly property int weightTitle: 600
    }

    /**
     * The settings window. Three depths set its parts apart by tone alone, a
     * step of at least four in lightness between each, with no lines: the
     * window for the rail, a pane for the page, plates on the pane. The
     * categories carry a colour each so they are known at a glance.
     */
    readonly property QtObject settings: QtObject {
        readonly property color window: root.dark ? "#17181c" : "#e4e7ec"
        readonly property color pane: root.dark ? "#202127" : "#f4f5f8"
        readonly property color plate: root.dark ? "#2a2b32" : "#ffffff"
        /** Sunk into a plate: a track, a disc behind a plain glyph. */
        readonly property color sunken: root.dark ? "#1f2026" : "#eceef2"
        readonly property color rule: root.dark ? "#14ffffff" : "#12000000"

        readonly property real railWidth: 288
        readonly property real railPadding: 12
        /** Where every leading glyph of the rail is centred. */
        readonly property real railAxis: 38
        readonly property real railItem: 44
        readonly property real railChip: 28
        readonly property real avatar: 28
        readonly property real search: 36

        /** The page's column, from the pane's left edge, no wider than reads well. */
        readonly property real contentWidth: 960
        readonly property real contentMargin: 40
        readonly property real contentTop: 20

        readonly property real paneRadius: 24
        readonly property real plateRadius: 16
        readonly property real controlRadius: 10
        readonly property real rowHeight: 56
        readonly property real rowPadding: 16
        readonly property real rowChip: 32
        readonly property real cardChip: 36
        readonly property real heroChip: 44

        /** The type scale: four steps, each its own role. */
        readonly property real small: 12
        readonly property real body: 14
        readonly property real heading: 16
        readonly property real display: 28
        /** Between groups, and between a group's label and its plate. */
        readonly property real groupGap: 24
        readonly property real labelGap: 8
    }

    /**
     * Converts OKLCH to an sRGB colour. The categories' colours are spaced in
     * a space where equal lightness looks equal, so every chip's glyph reads
     * against its disc alike; in HSL one hue's glyph read at 2.8 to 1 and
     * another's at 7.3.
     */
    function oklch(l: real, c: real, h: real): color {
        const rad = h * Math.PI / 180;
        const a = c * Math.cos(rad), b = c * Math.sin(rad);
        const l_ = l + 0.3963377774 * a + 0.2158037573 * b;
        const m_ = l - 0.1055613458 * a - 0.0638541728 * b;
        const s_ = l - 0.0894841775 * a - 1.2914855480 * b;
        const L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_;
        const lin = [
            4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
            -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
            -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        ];
        const gamma = x => {
            x = Math.max(0, Math.min(1, x));
            return x <= 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055;
        };
        return Qt.rgba(gamma(lin[0]), gamma(lin[1]), gamma(lin[2]), 1);
    }

    /**
     * A category's colour, as a chip's fill and the glyph on it, from one hue
     * in degrees: soft and light on a light desktop, deep and muted on a dark
     * one, so no category shouts over the others. A negative hue is the
     * neutral one, for what is no category.
     */
    function hue(degrees: real): var {
        const chroma = degrees < 0 ? 0 : 1;
        return root.dark
            ? { fill: root.oklch(0.34, 0.05 * chroma, degrees), ink: root.oklch(0.86, 0.08 * chroma, degrees) }
            : { fill: root.oklch(0.94, 0.035 * chroma, degrees), ink: root.oklch(0.50, 0.13 * chroma, degrees) };
    }

    readonly property QtObject motion: QtObject {
        readonly property int fast: 120
        readonly property int normal: 220
        readonly property int slow: 380
        readonly property var standard: [0.2, 0, 0, 1, 1, 1]
        readonly property var enter: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property var exit: [0.3, 0, 0.8, 0.15, 1, 1]
        /** Long and gentle at the end, for a panel arriving from the dock. */
        readonly property var decelerate: [0.33, 1, 0.68, 1, 1, 1]
    }
}
