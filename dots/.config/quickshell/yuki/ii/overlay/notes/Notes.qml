import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Notes")
    showCenterButton: true

    contentItem: NotesContent {
        radius: root.contentRadius
        isClickthrough: root.clickthrough
    }
}
