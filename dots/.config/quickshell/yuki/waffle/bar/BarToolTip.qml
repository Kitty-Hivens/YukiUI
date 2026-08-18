import QtQuick
import Quickshell
import qs.core
import qs.waffle.looks

WPopupToolTip {
    anchorEdges: Config.options.waffles.bar.bottom ? Edges.Top : Edges.Bottom
}
