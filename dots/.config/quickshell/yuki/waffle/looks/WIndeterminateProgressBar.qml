import QtQuick
import Qt5Compat.GraphicalEffects
import qs
import qs.core.services
import qs.core.services.network
import qs.core
import qs.common.widgets
import qs.waffle.looks

StyledIndeterminateProgressBar {
    id: progressBar
    implicitHeight: 3
    background: null
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: progressBar.width
            height: progressBar.height
            radius: progressBar.height / 2
        }
    }
}
