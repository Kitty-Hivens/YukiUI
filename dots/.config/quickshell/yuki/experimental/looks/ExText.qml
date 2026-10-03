import QtQuick

Text {
    /** "body", "label", "caption" or "title". */
    property string role: "body"
    property bool dim: false

    // Plain unless asked otherwise. Qt reads markup into any text that looks
    // like it, and much of what is shown is written by others: a window's
    // title, a program's polkit message. An <img> there made the shell fetch
    // whatever it pointed at, and other tags could restyle the message.
    textFormat: Text.PlainText
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
