import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core.services.network
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks
import qs.waffle.actionCenter

WChoiceButton {
    id: root

    property bool expanded: false
    checked: expanded
    clip: true

    horizontalPadding: 12
    verticalPadding: 6
    animateChoiceHighlight: false

    Behavior on implicitHeight {
        animation: Looks.transition.resize.createObject(this)
    }
    onClicked: expanded = !expanded
}
