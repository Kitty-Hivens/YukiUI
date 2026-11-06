import qs.core
import qs.common.widgets
import qs.core.functions
import qs.common
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell

// A picture from the clipboard history, as large as it fits, hidden behind a blur
// when asked.
Rectangle {
    id: root
    /** The path of the picture, as the history keeps it. */
    property string path
    property real maxWidth
    property real maxHeight
    property bool blur: false
    property string blurText: "Image hidden"

    readonly property real imageWidth: image.implicitWidth
    readonly property real imageHeight: image.implicitHeight
    property real scale: imageWidth > 0 && imageHeight > 0 ? Math.min(root.maxWidth / imageWidth, root.maxHeight / imageHeight, 1) : 0

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.small
    implicitHeight: imageHeight * scale
    implicitWidth: imageWidth * scale

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: image.width
            height: image.height
            radius: root.radius
        }
    }

    StyledImage {
        id: image
        anchors.fill: parent

        source: root.path.length > 0 ? FileUtils.fileUrl(root.path) : ""
        fillMode: Image.PreserveAspectFit
        antialiasing: true
        asynchronous: true
    }

    Loader {
        id: blurLoader
        active: root.blur
        anchors.fill: image
        sourceComponent: GaussianBlur {
            source: image
            radius: 35
            samples: radius * 2 + 1

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.5)

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    MaterialSymbol {
                        visible: width <= image.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "visibility_off"
                        font.pixelSize: 28
                    }
                    StyledText {
                        visible: width <= image.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.blurText
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.smallie
                    }
                }
            }
        }
    }
}
