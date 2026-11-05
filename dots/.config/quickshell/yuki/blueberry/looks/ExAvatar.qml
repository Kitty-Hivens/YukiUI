import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

import qs.core.services

// Who is signed in: their picture, the one AccountsService keeps or a ~/.face,
// or the first letter of their name on a disc while there is none. Looked for
// first rather than tried: an image that fails to open complains in the log.
Rectangle {
    id: root

    property int size: 28
    property string name: SystemInfo.username
    property color plate: ExLooks.colors.accent
    property color ink: ExLooks.colors.accentInk
    /** Changed after the picture has been replaced, to read it again. */
    property int revision: 0
    property string picture: ""

    onRevisionChanged: finder.running = true

    implicitWidth: root.size
    implicitHeight: root.size
    radius: root.size / 2
    color: root.plate

    Process {
        id: finder
        running: true
        command: ["sh", "-c", "for picture in \"/var/lib/AccountsService/icons/$USER\" \"$HOME/.face\" \"$HOME/.face.icon\"; do [ -s \"$picture\" ] && echo \"$picture\" && exit 0; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Through nothing first, or a picture replaced under the same
                // path would not be read again.
                root.picture = "";
                root.picture = text.trim();
            }
        }
    }

    ExText {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: (root.name || "?").charAt(0).toUpperCase()
        font.pixelSize: Math.round(root.size * 0.45)
        font.weight: ExLooks.font.weightTitle
        color: root.ink
    }
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: image.status === Image.Ready

        Image {
            id: image
            anchors.fill: parent
            source: root.picture.length > 0 ? `file://${root.picture}` : ""
            sourceSize: Qt.size(root.size * 2, root.size * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
    }
}
