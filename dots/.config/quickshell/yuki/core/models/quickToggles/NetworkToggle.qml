import QtQuick
import qs.core.services
import qs.core
import qs.core.functions
import qs.common.widgets

QuickToggleModel {
    name: Translation.tr("Internet")
    statusText: Network.vpnActive ? Translation.tr("VPN | %1").arg(Network.networkName) : Network.networkName
    tooltipText: (Network.vpnActive ? Translation.tr("Through %1").arg(Network.vpnDevice) + "\n" : "")
        + Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    icon: Network.materialSymbol

    toggled: Network.wifiStatus !== "disabled"
    mainAction: () => Network.toggleWifi()
    hasMenu: true
}
