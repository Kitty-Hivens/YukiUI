import QtQuick

Text {
    /** "body", "label", "caption" or "title". */
    property string role: "body"
    property bool dim: false

    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    color: dim ? ExLooks.colors.textDim : ExLooks.colors.text
    font {
        family: ExLooks.font.family
        hintingPreference: Font.PreferDefaultHinting
        pixelSize: role === "title" ? ExLooks.font.title
            : role === "label" ? ExLooks.font.label
            : role === "caption" ? ExLooks.font.caption
            : ExLooks.font.body
        weight: role === "title" ? ExLooks.font.weightTitle
            : role === "label" ? ExLooks.font.weightLabel
            : ExLooks.font.weightBody
    }
}
