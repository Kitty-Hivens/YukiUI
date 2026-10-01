import QtQuick

/**
 * A thin line with a stretch of accent running along it, for work that has no
 * end it can name: a scan for networks, a search for devices. Takes its
 * height whether running or not, so what lies under it does not move.
 */
Item {
    id: root

    property bool running: false

    implicitHeight: 3
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: ExLooks.colors.accent
        opacity: root.running ? 0.18 : 0

        Behavior on opacity {
            NumberAnimation { duration: ExLooks.motion.normal }
        }
    }

    Rectangle {
        id: runner

        width: root.width * 0.3
        height: root.height
        radius: height / 2
        color: ExLooks.colors.accent
        visible: root.running

        NumberAnimation on x {
            running: root.running && root.visible
            loops: Animation.Infinite
            from: -runner.width
            to: root.width
            duration: 1100
            easing.type: Easing.InOutQuad
        }
    }
}
