import QtQuick

import qs.experimental.looks

/**
 * How far something is into being shown, from 0 to 1, animated towards whether
 * it is wanted.
 *
 * It lives outside what it animates. Whatever it drives can then stay loaded
 * for as long as `present` holds, which is until it has played its way out,
 * rather than vanishing the moment it is no longer wanted.
 */
Item {
    id: root

    property bool wanted: false
    property real progress: 0
    readonly property bool present: root.wanted || root.progress > 0

    visible: false

    // Bound once it exists, so one made while already wanted still comes in
    // rather than starting at the end.
    Component.onCompleted: Qt.callLater(() => root.progress = Qt.binding(() => root.wanted ? 1 : 0))

    Behavior on progress {
        NumberAnimation {
            duration: root.wanted ? ExLooks.motion.normal : ExLooks.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.wanted ? ExLooks.motion.enter : ExLooks.motion.exit
        }
    }
}
