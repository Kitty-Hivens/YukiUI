//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.experimental.looks
import qs.experimental.gallery

// The experimental kit laid out for looking at. Run on its own, one page at a
// time:
//
//     qs -p experimentalGallery.qml
//     GALLERY_PAGE=flyout GALLERY_EDGE=left GALLERY_DOCK=island qs -p experimentalGallery.qml
//     GALLERY_PAGE=dock qs -p experimentalGallery.qml
ApplicationWindow {
    id: root

    readonly property string page: Quickshell.env("GALLERY_PAGE") || "controls"

    visible: true
    // Deliberately not translated: it is what a window rule would match on.
    title: "Experimental Gallery"
    width: pageLoader.item?.implicitWidth ?? 1000
    height: pageLoader.item?.implicitHeight ?? 720
    color: ExLooks.colors.background

    Loader {
        id: pageLoader
        anchors.fill: parent
        sourceComponent: root.page === "flyout" ? flyoutPage : (root.page === "dock" ? dockPage : controlsPage)
    }

    Component {
        id: controlsPage
        ControlsPage {}
    }

    Component {
        id: flyoutPage
        FlyoutPage {
            edge: Quickshell.env("GALLERY_EDGE") || "bottom"
            dockStyle: Quickshell.env("GALLERY_DOCK") || "attached"
        }
    }

    Component {
        id: dockPage
        DockPage {}
    }
}
