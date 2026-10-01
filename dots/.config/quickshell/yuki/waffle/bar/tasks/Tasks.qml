import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.core.services
import qs.core
import qs.waffle.looks

MouseArea {
    id: root

    required property var barScreen
    // Windows shows the windows of the desktop in use, and so does this.
    readonly property int workspaceId: Hyprland.monitorFor(root.barScreen)?.activeWorkspace?.id ?? -1

    Layout.fillHeight: true
    implicitHeight: appRow.implicitHeight
    implicitWidth: appRow.implicitWidth
    hoverEnabled: true

    function showPreviewPopup(appEntry, button) {
        previewPopup.show(appEntry, button);
    }

    Behavior on implicitWidth {
        animation: Looks.transition.move.createObject(this)
    }

    WListView {
        id: appRow
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        orientation: Qt.Horizontal
        spacing: 0
        implicitWidth: contentWidth
        clip: true
        interactive: false
        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.appsOn(root.workspaceId)
        }
        delegate: TaskAppButton {
            required property var modelData
            appEntry: modelData.entry
            workspaceId: root.workspaceId

            onHoverPreviewRequested: {
                root.showPreviewPopup(appEntry, this);
            }
            onHoverPreviewDismissed: {
                previewPopup.close();
            }
        }
    }

    // Previews popup
    TaskPreview {
        id: previewPopup
        tasksHovered: root.containsMouse
    }
}
