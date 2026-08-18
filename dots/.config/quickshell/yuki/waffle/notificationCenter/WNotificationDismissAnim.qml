import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.waffle.looks

SequentialAnimation {
    id: root

    required property var target

    PropertyAction {
        target: root.target
        property: "ListView.delayRemove"
        value: true
    }
    NumberAnimation {
        target: root.target
        property: "x"
        to: root.target.width
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Looks.transition.easing.bezierCurve.decelerate
    }
    PropertyAction {
        target: root.target
        property: "ListView.delayRemove"
        value: false
    }
}
