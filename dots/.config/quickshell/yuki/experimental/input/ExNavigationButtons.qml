import QtQuick

// The mouse's side buttons, as back and forward. Most mice send them as the
// side and extra buttons, which Qt calls back and forward. Some send the back
// and forward buttons proper, which reach Qt as its fourth and third extra
// buttons. Only these are taken: a press of any other button goes on to
// whatever is under it.
MouseArea {
    id: root

    signal back()
    signal forward()

    anchors.fill: parent
    acceptedButtons: Qt.BackButton | Qt.ForwardButton | Qt.ExtraButton3 | Qt.ExtraButton4
    onPressed: event => {
        if (event.button === Qt.BackButton || event.button === Qt.ExtraButton4)
            root.back();
        else
            root.forward();
    }
}
