pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.waffle.looks

StyledImage {
    id: avatar
    Layout.alignment: Qt.AlignTop
    sourceSize: Qt.size(32, 32)
    primarySource: Directories.userAvatarPathAccountsService
    fallbacks: [Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Circle {
            diameter: avatar.height
        }
    }
}
