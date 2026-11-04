import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.core
import qs.core.functions
import qs.blueberry.desktop

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData

        FullscreenMapGuard {
            id: mapGuard
            screenName: window.modelData.name
        }

        visible: mapGuard.mapped
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        // The lowest layer, the desktop icons on it with the wallpaper: under
        // every window and under the dock. On a layer it shared with the dock,
        // drawn over the whole screen and made after it, it covered the dock,
        // which goes down to the layer above this one under a fullscreen window.
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:background"
        // Keys only while an icon is picked, so Delete and the arrows reach
        // it. Taking them otherwise would let a pointer resting on the empty
        // desktop take the keyboard from the window being typed into.
        WlrLayershell.keyboardFocus: !(icons.item?.wantsKeys ?? false) ? WlrKeyboardFocus.None
            : icons.item.seizing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "black"

        // Two pictures taking turns. A new wallpaper is decoded into the one
        // behind, and once it is ready it fades in over the other, which is
        // let go of afterwards. Swapped straight in, the screen went black for
        // as long as the file took to decode and then jumped to the new one.
        readonly property string wanted: Config.options.background.wallpaperPath
        property bool firstOnTop: true

        onWantedChanged: window.show(window.wanted)
        Component.onCompleted: {
            first.path = window.wanted;
            first.opacity = 1;
        }

        function show(path: string) {
            // A change in the middle of a fade finishes that one first, so
            // the picture behind it is not swapped out while still in sight.
            if (fade.running)
                fade.complete();
            const incoming = window.firstOnTop ? second : first;
            incoming.opacity = 0;
            incoming.path = path;
        }

        function landed(image) {
            if (image.status !== Image.Ready || image.opacity !== 0 || image.path !== window.wanted)
                return;
            window.firstOnTop = image === first;
            fade.target = image;
            fade.start();
        }

        component Wallpaper: Image {
            property string path: ""

            anchors.fill: parent
            source: FileUtils.fileUrl(path)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            // Decoded at the size of the screen, not of the file.
            sourceSize: Qt.size(window.width, window.height)
        }

        Wallpaper {
            id: first
            z: window.firstOnTop ? 1 : 0
            opacity: 0
            onStatusChanged: window.landed(first)
        }
        Wallpaper {
            id: second
            z: window.firstOnTop ? 0 : 1
            opacity: 0
            onStatusChanged: window.landed(second)
        }

        NumberAnimation {
            id: fade

            property: "opacity"
            from: 0
            to: 1
            duration: 500
            easing.type: Easing.OutCubic
            onFinished: {
                const behind = fade.target === first ? second : first;
                behind.path = "";
            }
        }

        // On one screen only, the way Windows keeps them to the main one. With
        // no main screen to ask the compositor for, the one furthest left, and
        // of those the highest, stands in for it.
        Loader {
            id: icons
            anchors.fill: parent
            z: 2
            active: window.modelData === [...Quickshell.screens].sort((a, b) => a.x - b.x || a.y - b.y)[0]
            sourceComponent: ExDesktopIcons {
                screenModel: window.modelData
            }
        }
    }
}
