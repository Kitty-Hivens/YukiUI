import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

MouseArea {
    id: root

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
        // TODO: Include only apps (and windows) in current workspace only | wait, does that even make sense in a Hyprland workflow?
        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps.filter(app => app.appId !== "SEPARATOR")
        }
        delegate: TaskAppButton {
            required property var modelData
            appEntry: modelData

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

        /// Asked once and held, rather than left as a binding on the attached object.
        /// Unmapping the bar tears its item tree down, and the cascade of derefWindow
        /// calls reaches this MouseArea; anything still bound underneath is evaluated
        /// again from inside that teardown, and this one would ask an item whose
        /// window is already gone, which segfaults the shell.
        property var barWindow: null
        anchor.window: previewPopup.barWindow
        Component.onCompleted: previewPopup.barWindow = root.QsWindow.window
    }
}
