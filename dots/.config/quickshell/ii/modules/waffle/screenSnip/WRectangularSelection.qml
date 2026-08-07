import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

Item {
    id: root

    required property int regionX
    required property int regionY
    required property int regionWidth
    required property int regionHeight

    property bool dashed: true
    property color borderColor: "#ffffff"
    property color overlayColor: ColorUtils.transparentize("#000000", 1)
    Component.onCompleted: overlayColor = ColorUtils.transparentize("#000000", 0.4)
    Behavior on overlayColor {
        ColorAnimation {
            duration: 150
            easing.type: Easing.InOutQuad
        }
    }

    /// Everything outside the selection, as four bands measured from this item's own
    /// edges. Drawn before as one rectangle with a border thick enough to reach
    /// them, the thickness came from this item's size -- which is nothing until the
    /// layout has run, so the first frames darkened a strip near one edge and left
    /// the rest of the screen alone.
    readonly property int shadeLeft: Math.max(0, Math.min(root.regionX, root.width))
    readonly property int shadeTop: Math.max(0, Math.min(root.regionY, root.height))
    readonly property int shadeRight: Math.max(0, Math.min(root.regionX + root.regionWidth, root.width))
    readonly property int shadeBottom: Math.max(0, Math.min(root.regionY + root.regionHeight, root.height))

    component Shade: Rectangle {
        z: 1
        color: root.overlayColor
    }

    Shade {
        x: 0
        y: 0
        width: root.width
        height: root.shadeTop
    }
    Shade {
        x: 0
        y: root.shadeBottom
        width: root.width
        height: Math.max(0, root.height - root.shadeBottom)
    }
    Shade {
        x: 0
        y: root.shadeTop
        width: root.shadeLeft
        height: Math.max(0, root.shadeBottom - root.shadeTop)
    }
    Shade {
        x: root.shadeRight
        y: root.shadeTop
        width: Math.max(0, root.width - root.shadeRight)
        height: Math.max(0, root.shadeBottom - root.shadeTop)
    }

    // Selection border
    DashedBorder {
        id: border
        z: 2
        visible: root.regionWidth > 0 && root.regionHeight > 0
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX - borderWidth)
            topMargin: Math.round(root.regionY - borderWidth)
        }
        width: Math.round(root.regionWidth + borderWidth * 2)
        height: Math.round(root.regionHeight + borderWidth * 2)
        color: root.borderColor
        dashLength: 4
        gapLength: root.dashed ? 3 : 0
        borderWidth: 1
    }
}
