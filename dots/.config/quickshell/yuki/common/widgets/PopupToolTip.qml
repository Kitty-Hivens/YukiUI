pragma ComponentBehavior: Bound
import qs.core
import qs.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property string text: ""
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    property real horizontalMargin: horizontalPadding
    property real verticalMargin: verticalPadding
    
    function updateAnchor() {
        tooltipLoader.item?.anchor.updateAnchor();
    }

    readonly property bool internalVisibleCondition: (extraVisibleCondition && (parent.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition
    property var anchorEdges: Edges.Top
    property var anchorGravity: anchorEdges

    property Item contentItem: StyledToolTipContent {
        id: contentItem
        anchors.centerIn: parent
        text: root.text
        shown: false
        Component.onCompleted: shown = true
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }

    Loader {
        id: tooltipLoader
        anchors.fill: parent
        active: root.internalVisibleCondition
        sourceComponent: PopupWindow {
            id: tooltipWindow
            visible: true
            // Anchored to the window, with the box of the item it explains worked
            // out each time it is placed, and never to that item: a null anchor
            // item makes Quickshell 0.3.0 ask the null for its window and
            // segfault, and the parent reads as null while it is being torn down.
            // The window is taken once, since a binding on it is what used to
            // crash the shell when a bar was unmapped under a fullscreen game.
            Component.onCompleted: tooltipWindow.anchor.window = root.QsWindow.window
            anchor {
                edges: root.anchorEdges
                gravity: root.anchorGravity
                onAnchoring: {
                    const target = root.parent;
                    if (!target)
                        return;
                    const corner = target.mapToItem(null, 0, 0);
                    tooltipWindow.anchor.rect.x = Math.round(corner.x);
                    tooltipWindow.anchor.rect.y = Math.round(corner.y);
                    tooltipWindow.anchor.rect.width = Math.max(1, Math.round(target.width));
                    tooltipWindow.anchor.rect.height = Math.max(1, Math.round(target.height));
                }
            }
            mask: Region {
                item: null
            }

            color: "transparent"
            implicitWidth: root.contentItem.implicitWidth + root.horizontalMargin * 2
            implicitHeight: root.contentItem.implicitHeight + root.verticalMargin * 2

            data: [root.contentItem]
        }
    }
}
