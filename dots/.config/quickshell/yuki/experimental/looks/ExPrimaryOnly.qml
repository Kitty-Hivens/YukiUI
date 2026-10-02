import QtQuick

// Keeps a button to the left mouse button. Placed inside one, over all of it.
//
// A Qt Quick Controls button turns down a press of any other button, and yet a
// middle press that moves the pointer a little before it is let go clicked it
// all the same: the move marks the button pressed, and letting go then counts
// as a click. In the dock the right button did the same. The pointer of a real
// mouse nearly always moves a pixel or two, so a middle or right click on the
// dock's launcher button opened the launcher. These presses are taken here
// instead, and never reach the button. What the right button is to do, a
// button says through `rightClicked`.
MouseArea {
    signal rightClicked

    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onClicked: event => {
        if (event.button === Qt.RightButton)
            rightClicked();
    }
}
