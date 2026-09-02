pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import qs.core
import qs.core.functions
import qs.core.services
import qs.core.utils
import qs.common.widgets
import qs.ii.overlay
import qs.common

StyledOverlayWidget {
    id: root
    showClickabilityButton: false
    resizable: false
    clickthrough: true

    property string imageSource: Config.options.overlay.floatingImage.imageSource
    property real scaleFactor: Config.options.overlay.floatingImage.scale
    property int imageWidth: 0
    property int imageHeight: 0
    readonly property bool hasImage: root.imageWidth > 0 && root.imageHeight > 0

    // Override to always save 0 size
    function savePosition(xPos = root.x, yPos = root.y, width = 0, height = 0) {
        root.persistentStateEntry.x = Math.round(xPos);
        root.persistentStateEntry.y = Math.round(yPos);
        root.persistentStateEntry.width = 0
        root.persistentStateEntry.height = 0
    }

    onImageSourceChanged: {
        imageDownloader.running = false;
        animatedImage.source = "";
        root.imageWidth = 0;
        root.imageHeight = 0;
        if (root.imageSource.length === 0)
            return;
        imageDownloader.sourceUrl = root.imageSource;
        imageDownloader.filePath = Qt.resolvedUrl(Directories.tempImages + "/" + Qt.md5(root.imageSource))
        imageDownloader.running = true;
    }

    contentItem: OverlayBackground {
        id: bg
        color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, root.actuallyPinned ? 1 : 0)
        radius: root.contentRadius

        // Sized from the picture rather than by assigning into these, so that a
        // widget with no picture still has somewhere to say so.
        implicitWidth: root.hasImage ? root.imageWidth * root.scaleFactor : placeholder.implicitWidth + 32
        implicitHeight: root.hasImage ? root.imageHeight * root.scaleFactor : placeholder.implicitHeight + 32

        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y < 0) {
                    Config.options.overlay.floatingImage.scale = Math.max(0.1, Config.options.overlay.floatingImage.scale - 0.1);
                }
                else if (event.angleDelta.y > 0) {
                    Config.options.overlay.floatingImage.scale = Math.min(5.0, Config.options.overlay.floatingImage.scale + 0.1);
                }
            }
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bg.width
                height: bg.height
                radius: bg.radius
            }
        }

        StyledText {
            id: placeholder
            anchors.centerIn: parent
            visible: !root.hasImage
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
            text: root.imageSource.length === 0
                ? Translation.tr("No picture set.\nName one in the overlay settings.")
                : Translation.tr("Could not load the picture.")
        }

        AnimatedImage {
            id: animatedImage
            anchors.centerIn: parent
            visible: root.hasImage
            width: root.imageWidth * root.scaleFactor
            height: root.imageHeight * root.scaleFactor
            // The size it was decoded at, not the size it is drawn at. Reading
            // the window for a pixel ratio here is a live binding onto a window
            // that gets destroyed under it, and tying it to the drawn size made
            // every notch of the scroll wheel decode the picture again.
            sourceSize: root.hasImage ? Qt.size(root.imageWidth, root.imageHeight) : undefined

            playing: visible
            asynchronous: true
            source: ""

            ImageDownloaderProcess {
                id: imageDownloader
                filePath: Qt.resolvedUrl(Directories.tempImages + "/" + Qt.md5(root.imageSource))
                sourceUrl: root.imageSource

                onDone: (path, width, height) => {
                    root.imageWidth = width;
                    root.imageHeight = height;
                    animatedImage.source = path;
                }
            }
        }
    }
}
