import QtQuick

Text {
    property real size: ExLooks.sizes.icon
    property real fill: 0

    width: size
    height: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    // Native rendering leaves a seam in filled glyphs once they grow large.
    renderType: size >= 40 ? Text.QtRendering : Text.NativeRendering
    color: ExLooks.colors.text
    font {
        family: ExLooks.font.glyphs
        hintingPreference: Font.PreferNoHinting
        pixelSize: size
        variableAxes: ({ "FILL": fill, "opsz": Math.min(48, Math.max(20, size)), "wght": 400 })
    }
}
