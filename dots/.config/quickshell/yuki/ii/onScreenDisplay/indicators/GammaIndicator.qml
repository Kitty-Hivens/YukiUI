import qs.core.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.ii.onScreenDisplay

OsdValueIndicator {
    id: rotateIcon

    icon: "wb_twilight"
    name: Translation.tr("Gamma")
    from: Hyprsunset.gammaLowerLimit / 100
    value: Hyprsunset.gamma / 100 ?? 0.5
}
