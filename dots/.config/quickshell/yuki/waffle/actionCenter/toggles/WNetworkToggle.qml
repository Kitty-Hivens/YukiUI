import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks
import qs.waffle.actionCenter

ActionCenterToggle {
    id: root

    name: Network.ethernet ? Translation.tr("Network") : Network.networkName


}
