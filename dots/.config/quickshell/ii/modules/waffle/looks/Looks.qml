pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root
    property QtObject darkColors
    property QtObject lightColors
    property QtObject colors
    property QtObject radius
    property QtObject font
    property QtObject transition
    property string iconsPath: `${Directories.assetsPath}/icons/fluent`
    property bool dark: Appearance.m3colors.darkmode

    readonly property bool transparencyEnabled: Config.options.appearance.transparency.enable
    property real backgroundTransparency: transparencyEnabled ? 0.16 : 0
    property real panelBackgroundTransparency: transparencyEnabled ? 0.14 : 0
    property real panelLayerTransparency: root.dark ? 0.9 : 0.7
    property real contentTransparency: root.dark ? 0.87 : 0.5
    function applyBackgroundTransparency(col) {
        return ColorUtils.applyAlpha(col, 1 - root.backgroundTransparency)
    }
    function applyContentTransparency(col) {
        return ColorUtils.applyAlpha(col, 1 - root.contentTransparency)
    }
    lightColors: QtObject {
        id: lightColors
        property color bgPanelBody: "#F2F2F2"
        property color bgPanelSeparator: "#E0E0E0"
        property color bg0: "#EEEEEE"
        property color bg0Border: '#BEBEBE'
        property color bg1Base: "#F7F7F7"
        property color bg1: "#F7F7F7"
        property color bg1Hover: "#F7F7F7"
        property color bg1Active: '#EFEFEF'
        property color bg1Border: '#E9E9E9'
        property color bg2: "#FBFBFB"
        property color bg2Base: "#FBFBFB"
        property color bg2Hover: '#ffffff'
        property color bg2Active: '#eeeeee'
        property color bg2Border: '#E0E0E0'
        property color subfg: "#5C5C5C"
        property color fg: "#000000"
        property color fg1: "#626262"
        property color inactiveIcon: "#C4C4C4"
        property color controlBgInactive: '#555458'
        property color controlBg: '#807F85'
        property color controlBgHover: '#57575B'
        property color controlFg: "#FFFFFF"
        property color accentUnfocused: "#848484"
        property color link: "#235CCF"
        property color inputBg: ColorUtils.transparentize(bg0, 0.4)
    }
    darkColors: QtObject {
        id: darkColors
        property color bgPanelBody: '#242424'
        property color bgPanelSeparator: "#191919"
        property color bg0: "#1C1C1C"
        property color bg0Border: "#404040"
        property color bg1Base: '#2C2C2C'
        property color bg1: '#2C2C2C'
        property color bg1Hover: "#292929"
        property color bg1Active: '#252525'
        property color bg1Border: '#bebebe'
        property color bg2Base: "#313131"
        property color bg2: '#313131'
        property color bg2Hover: '#363636'
        property color bg2Active: '#2B2B2B'
        property color bg2Border: '#404040'
        property color subfg: "#CED1D7"
        property color fg: "#FFFFFF"
        property color fg1: "#D1D1D1"
        property color inactiveIcon: "#494949"
        property color controlBgInactive: "#CDCECF"
        property color controlBg: "#9B9B9B"
        property color controlBgHover: "#CFCED1"
        property color controlFg: "#454545"
        property color accentUnfocused: "#989898"
        property color link: "#A7C9FC"
        property color inputBg: ColorUtils.transparentize(darkColors.bg0, 0.5)
    }
    colors: QtObject {
        id: colors
        // Special
        property color shadow: ColorUtils.transparentize('#161616', 0.62)
        property color ambientShadow: ColorUtils.transparentize("#000000", 0.75)
        property color bgPanelFooterBase: root.dark ? root.darkColors.bg0 : root.lightColors.bg0
        property color bgPanelFooterBackground: ColorUtils.transparentize(root.dark ? root.darkColors.bg0 : root.lightColors.bg0, root.panelBackgroundTransparency)
        property color bgPanelFooter: ColorUtils.transparentize(bgPanelFooterBackground, root.panelLayerTransparency)
        property color bgPanelBodyBase: root.dark ? root.darkColors.bgPanelBody : root.lightColors.bgPanelBody
        property color bgPanelBody: ColorUtils.solveOverlayColor(bgPanelFooterBackground,bgPanelBodyBase, 1 - root.panelLayerTransparency)
        property color bgPanelSeparator: ColorUtils.solveOverlayColor(bgPanelBodyBase, root.dark ? root.darkColors.bgPanelSeparator : root.lightColors.bgPanelSeparator, 1 - root.panelBackgroundTransparency)
        // Layer 0
        property color bg0Base: root.dark ? root.darkColors.bg0 : root.lightColors.bg0
        property color bg0: ColorUtils.transparentize(bg0Base, root.backgroundTransparency)
        property color bg0Border: ColorUtils.transparentize(root.dark ? root.darkColors.bg0Border : root.lightColors.bg0Border, root.backgroundTransparency)
        // Layer 1
        property color bg1Base: root.dark ? root.darkColors.bg1 : root.lightColors.bg1
        property color bg1: ColorUtils.solveOverlayColor(bg0Base, bg1Base, 1 - root.contentTransparency)
        property color bg1Hover: ColorUtils.solveOverlayColor(bg0Base, root.dark ? root.darkColors.bg1Hover : root.lightColors.bg1Hover, 1 - root.contentTransparency)
        property color bg1Active: ColorUtils.solveOverlayColor(bg0Base, root.dark ? root.darkColors.bg1Active : root.lightColors.bg1Active, 1 - root.contentTransparency)
        property color bg1Border: ColorUtils.solveOverlayColor(bg0Base, root.dark ? root.darkColors.bg1Border : root.lightColors.bg1Border, 1 - root.contentTransparency)
        // Layer 2
        property color bg2Base: root.dark ? root.darkColors.bg2 : root.lightColors.bg2
        property color bg2: ColorUtils.solveOverlayColor(bgPanelBodyBase, bg2Base, 1 - root.contentTransparency)
        property color bg2Hover: ColorUtils.solveOverlayColor(bgPanelBodyBase, root.dark ? root.darkColors.bg2Hover : root.lightColors.bg2Hover, 1 - root.contentTransparency)
        property color bg2Active: ColorUtils.solveOverlayColor(bgPanelBodyBase, root.dark ? root.darkColors.bg2Active : root.lightColors.bg2Active, 1 - root.contentTransparency)
        property color bg2Border: ColorUtils.solveOverlayColor(bgPanelBodyBase, root.dark ? root.darkColors.bg2Border : root.lightColors.bg2Border, 1 - root.contentTransparency)
        // Foreground / Text
        property color subfg: root.dark ? root.darkColors.subfg : root.lightColors.subfg
        property color fg: root.dark ? root.darkColors.fg : root.lightColors.fg
        property color fg1: root.dark ? root.darkColors.fg1 : root.lightColors.fg1
        property color inactiveIcon: root.dark ? root.darkColors.inactiveIcon : root.lightColors.inactiveIcon
        property color link: root.dark ? root.darkColors.link : root.lightColors.link
        // Controls
        property color controlBgInactive: root.dark ? root.darkColors.controlBgInactive : root.lightColors.controlBgInactive
        property color controlBg: root.dark ? root.darkColors.controlBg : root.lightColors.controlBg
        property color controlBgHover: root.dark ? root.darkColors.controlBgHover : root.lightColors.controlBgHover
        property color controlFg: root.dark ? root.darkColors.controlFg : root.lightColors.controlFg
        property color inputBg: root.dark ? root.darkColors.inputBg : root.lightColors.inputBg
        property color danger: "#C42B1C"
        property color dangerActive: "#B62D1F"
        property color warning: "#FF9900"
        // Accent
        property color accent: Appearance.colors.colPrimary
        property color accentHover: Appearance.colors.colPrimaryHover
        property color accentActive: Appearance.colors.colPrimaryActive
        property color accentUnfocused: root.dark ? root.darkColors.accentUnfocused : root.lightColors.accentUnfocused
        property color accentFg: ColorUtils.isDark(accent) ? "#FFFFFF" : "#000000"
        property color selection: Appearance.colors.colPrimaryContainer
        property color selectionFg: Appearance.colors.colOnPrimaryContainer
    }

    /// Measurements shared by more than one place. Everything here was a literal
    /// repeated across files -- the same page height in four control pages, the same
    /// width in the start menu and the panel that stands beside it -- so changing one
    /// of them meant finding the rest. The values are unchanged.
    property QtObject sizes: QtObject {
        id: sizes
        /// The bar.
        property int barHeight: 48
        /// A control page inside the action centre: Wi-Fi, Bluetooth, sound, night light.
        property int controlPageHeight: 400
        /// The button along the trailing edge of a row in one of those pages.
        property int controlActionWidth: 148
        /// The start menu, and the search panel that takes its place.
        property int menuWidth: 832
        /// A notification, in the popup stack and in the centre.
        property int notificationWidth: 396
    }

    radius: QtObject {
        id: radius
        property int none: 0
        property int small: 2
        property int medium: 4
        property int large: 8
        property int xLarge: 12
    }

    font: QtObject {
        id: font
        property QtObject family: QtObject {
            property string ui: "Noto Sans"
        }
        property QtObject weight: QtObject { // Noto is not Segoe, so we might use slightly different weights
            property int thin: Font.Normal
            property int regular: Font.Medium
            property int strong: Font.DemiBold
            property int stronger: (Font.DemiBold + 2*Font.Bold) / 3
            property int strongest: Font.Bold
        }
        property QtObject pixelSize: QtObject {
            property real normal: 11
            property real large: 13
            property real larger: 15
            property real xlarger: 17
        }
    }

    transition: QtObject {
        id: transition

        property int velocity: 850

        property QtObject easing: QtObject {
            // Fluent's three curves, named for what they do rather than for the CSS
            // keywords: what was called easeIn decelerates and what was called
            // easeOut accelerates, which is the right way round for entering and
            // leaving but reads backwards at every use. Both were also degenerate --
            // a control point in the corner starts at full speed, so panels arrived
            // with a snap instead of settling.
            property QtObject bezierCurve: QtObject {
                /// Entering: quick off the mark, long settle.
                readonly property list<real> decelerate: [0.1, 0.9, 0.2, 1.0, 1, 1]
                /// Leaving: gentle release, then away.
                readonly property list<real> accelerate: [0.7, 0.0, 1.0, 0.5, 1, 1]
                /// Moving between two places on screen.
                readonly property list<real> standard: [0.8, 0.0, 0.2, 1.0, 1, 1]
            }
        }

        property Component color: Component {
            ColorAnimation {
                duration: 80
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component opacity: Component {
            NumberAnimation {
                duration: 120
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component resize: Component { // TODO: better curve needed
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component enter: Component {
            NumberAnimation {
                duration: 250
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component exit: Component {
            NumberAnimation {
                duration: 250
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.accelerate
            }
        }

        property Component move: Component {
            NumberAnimation {
                duration: 170
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.standard
            }
        }

        property Component rotate: Component {
            NumberAnimation {
                duration: 170
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.standard
            }
        }

        property Component anchor: Component {
            AnchorAnimation {
                duration: 160
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component longMovement: Component {
            NumberAnimation {
                duration: 1000
                easing.type: Easing.BezierSpline
                easing.bezierCurve: transition.easing.bezierCurve.decelerate
            }
        }

        property Component scroll: Component {
            NumberAnimation {
                duration: 250
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.0, 0.0, 0.25, 1.0, 1, 1]
            }
        }
    }
}
