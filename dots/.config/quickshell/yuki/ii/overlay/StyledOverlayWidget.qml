pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects
import qs
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.common.widgets.widgetCanvas
import qs.common
import qs.ii

/*
 * To make an overlay widget:
 * 1. Create an ii/overlay/<yourWidget>/<YourWidget>.qml, using this as the base class and declare your widget content as contentItem
 * 2. Add an entry to OverlayContext.availableWidgets with identifier=<yourWidgetIdentifier>
 * 3. Add an entry in Persistent.states.overlay.<yourWidgetIdentifier> with x, y, width, height, pinned, clickthrough properties set to reasonable defaults
 * 4. Add an entry in OverlayWidgetDelegateChooser with roleValue=<yourWidgetIdentifier> and Declare your widget in there
 * Use existing entries as reference.
 */
AbstractOverlayWidget {
    id: root

    // To be defined by subclasses
    required property Item contentItem
    property bool fancyBorders: true
    property bool showCenterButton: false
    property bool showClickabilityButton: true

    // Defaults n stuff
    required property var modelData
    readonly property string identifier: modelData.identifier
    readonly property string materialSymbol: modelData.materialSymbol ?? "widgets"
    property string title: identifier.replace(/([A-Z])/g, " $1").replace(/^./, function(str){ return str.toUpperCase(); })
    property var persistentStateEntry: Persistent.states.overlay[identifier]
    property real radius: Appearance.rounding.windowRounding
    property real minimumWidth: contentItem.implicitWidth
    property real minimumHeight: contentItem.implicitHeight
    property real resizeMargin: 8
    property real padding: 6
    property real contentRadius: radius - padding

    // Resizing
    function getXResizeDirection(x) {
        return (x < root.resizeMargin) ? -1 : (x > root.width - root.resizeMargin) ? 1 : 0
    }
    function getYResizeDirection(y) {
        return (y < root.resizeMargin) ? -1 : (y > root.height - root.resizeMargin) ? 1 : 0
    }
    hoverEnabled: true
    property bool resizable: true
    property bool resizing: false
    property int resizeXDirection: getXResizeDirection(mouseX)
    property int resizeYDirection: getYResizeDirection(mouseY)
    draggable: IiStates.overlayOpen
    drag.target: undefined
    animateXPos: !dragHandler.active
    animateYPos: !dragHandler.active
    z: dragHandler.active ? 2 : 1
    /// Which resize cursor the press started on, kept for as long as it lasts.
    property int heldCursorShape: Qt.ArrowCursor
    cursorShape: {
        if (dragHandler.active) return root.resizing ? root.heldCursorShape : Qt.ArrowCursor;
        if (resizeMargin < mouseX && mouseX < width - resizeMargin &&
            resizeMargin < mouseY && mouseY < height - resizeMargin) {
            return Qt.ArrowCursor;
        } else {
            if (!root.resizable) return Qt.ArrowCursor;
            const dragIsLeft = mouseX < width / 2
            const dragIsTop = mouseY < height / 2
            if ((dragIsLeft && dragIsTop) || (!dragIsLeft && !dragIsTop)) {
                return Qt.SizeFDiagCursor
            } else {
                return Qt.SizeBDiagCursor
            }
        }
    }

    // Positioning & sizing
    x: Math.round(persistentStateEntry.x) // Round or it'll be blurry
    y: Math.round(persistentStateEntry.y) // Round or it'll be blurry
    pinned: persistentStateEntry.pinned
    clickthrough: persistentStateEntry.clickthrough
    opacity: (IiStates.overlayOpen || !clickthrough) ? 1.0 : Config.options.overlay.clickthroughOpacity

    // Guarded states & registration funcs
    readonly property bool open: Persistent.states.overlay.open.includes(root.identifier)
    readonly property bool actuallyPinned: pinned && open
    readonly property bool actuallyClickable: !clickthrough && actuallyPinned
    onActuallyClickableChanged: reportClickableState();
    function reportClickableState() {
        OverlayContext.registerClickableWidget(contentItem, actuallyClickable);
    }

    // Self-registeration with OverlayContext
    Component.onCompleted: reportClickableState()

    /**
     * Closing a widget destroys it, and a destroyed object announces nothing.
     *
     * Left registered, its content item stayed in the clickable list for the
     * rest of the session as an entry that reads back as null without the list
     * ever saying it changed. The window went on claiming keyboard focus for it,
     * and the compositor went on catching clicks in the rectangle where it used
     * to be: Quickshell drops a destroyed item from a region without telling the
     * window to work its input area out again.
     */
    Component.onDestruction: OverlayContext.registerClickableWidget(contentItem, false)

    Connections {
        target: OverlayContext
        function onRequestCenter(identifier) {
            if (identifier === root.identifier) {
                root.center()
            }
        }
    }

    // Hooks
    onPressed: (event) => {
        // We're only interested in handling resize here
        // Early returns
        if (!root.resizable) return;
        if (root.resizeMargin < event.x && event.x < root.width - root.resizeMargin &&
            root.resizeMargin < event.y && event.y < root.height - root.resizeMargin) {
            return;
        }
        // Resizing setup
        root.heldCursorShape = root.cursorShape;
        root.resizing = true;
        root.resizeXDirection = getXResizeDirection(event.x);
        root.resizeYDirection = getYResizeDirection(event.y);
        if (root.resizeYDirection !== 0 && root.resizeXDirection === 0) {
            root.resizeXDirection = event.x < root.width / 2 ? -1 : 1;
        } else if (root.resizeXDirection !== 0 && root.resizeYDirection === 0) {
            root.resizeYDirection = event.y < root.height / 2 ? -1 : 1;
        }
    }
    /**
     * A press on the border that never turned into a drag.
     *
     * The handler below never went active, so its release never ran either, and
     * the resize stayed armed: the next drag then resized the widget instead of
     * moving it, along the axis of whichever border was clicked before, and saved
     * the size that came out of it.
     */
    onReleased: root.resizing = false
    onPositionChanged: (event) => {
        if (!resizing) return;
        contentContainer.implicitWidth = Math.max(root.persistentStateEntry.width + dragHandler.xAxis.activeValue * root.resizeXDirection, root.minimumWidth);
        contentContainer.implicitHeight = Math.max(root.persistentStateEntry.height + dragHandler.yAxis.activeValue * root.resizeYDirection, root.minimumHeight);
        const negativeXDrag = root.resizeXDirection === -1;
        const negativeYDrag = root.resizeYDirection === -1;
        const wantedX = root.persistentStateEntry.x + (negativeXDrag ? dragHandler.xAxis.activeValue : 0)
        const wantedY = root.persistentStateEntry.y + (negativeYDrag ? dragHandler.yAxis.activeValue : 0)
        const negativeXDragLimit = root.persistentStateEntry.x + root.persistentStateEntry.width - contentContainer.implicitWidth;
        const negativeYDragLimit = root.persistentStateEntry.y + root.persistentStateEntry.height - contentContainer.implicitHeight;
        root.x = negativeXDrag ? Math.min(wantedX, negativeXDragLimit) : wantedX;
        root.y = negativeYDrag ? Math.min(wantedY, negativeYDragLimit) : wantedY;
    }
    DragHandler {
        id: dragHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        target: (root.draggable && !root.resizing) ? root : null
        onActiveChanged: { // Handle drag release
            if (!active) {
                root.resizing = false;
                root.savePosition();
            }
        }
        xAxis.minimum: 0
        xAxis.maximum: root.parent?.width - root.width
        yAxis.minimum: 0
        yAxis.maximum: root.parent?.height - root.height
    }

    function close() {
        Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== root.identifier);
    }

    function togglePinned() {
        persistentStateEntry.pinned = !persistentStateEntry.pinned;
    }

    function toggleClickthrough() {
        persistentStateEntry.clickthrough = !persistentStateEntry.clickthrough;
    }

    function savePosition(xPos = root.x, yPos = root.y, width = contentContainer.implicitWidth, height = contentContainer.implicitHeight) {
        persistentStateEntry.x = Math.round(xPos);
        persistentStateEntry.y = Math.round(yPos);
        persistentStateEntry.width = Math.round(width);
        persistentStateEntry.height = Math.round(height);
    }

    /**
     * Positions are absolute pixels, kept across restarts and monitor changes,
     * and nothing bounds them on the way in. The drag bounds them, which is no
     * help for a widget that is already past the edge and cannot be grabbed.
     * The saved spot of a widget from a wide screen is off a narrow one.
     */
    function clampIntoCanvas() {
        const canvas = root.parent;
        if (!canvas || canvas.width <= 0 || canvas.height <= 0) return;
        if (root.width <= 0 || root.height <= 0) return;
        const wantedX = Math.min(Math.max(root.x, 0), Math.max(0, canvas.width - root.width));
        const wantedY = Math.min(Math.max(root.y, 0), Math.max(0, canvas.height - root.height));
        if (wantedX === root.x && wantedY === root.y) return;
        root.x = wantedX;
        root.y = wantedY;
        // Position only. The defaults of savePosition read the size back out of
        // the content container, and being moved is not being resized.
        root.savePosition(wantedX, wantedY, root.persistentStateEntry.width, root.persistentStateEntry.height);
    }

    // Waited out: size and placement both settle over several passes as the
    // content lays itself out, and clamping against a half-built box moves a
    // widget that was never out of bounds.
    Timer {
        id: clampTimer
        interval: 0
        onTriggered: root.clampIntoCanvas()
    }
    onWidthChanged: clampTimer.restart()
    onHeightChanged: clampTimer.restart()
    Connections {
        target: root.parent
        function onWidthChanged() { clampTimer.restart(); }
        function onHeightChanged() { clampTimer.restart(); }
    }

    function center() {
        const targetX = (root.parent.width - contentColumn.width) / 2 - root.resizeMargin
        const targetY = (root.parent.height - contentContainer.height) / 2 - titleBar.implicitHeight + border.border.width - root.resizeMargin
        root.x = targetX
        root.y = targetY
        root.savePosition(targetX, targetY)
    }

    visible: IiStates.overlayOpen || actuallyPinned
    implicitWidth: contentColumn.implicitWidth + resizeMargin * 2
    implicitHeight: contentColumn.implicitHeight + resizeMargin * 2

    Rectangle {
        id: border
        anchors {
            fill: parent
            margins: root.resizeMargin
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, (root.fancyBorders && IiStates.overlayOpen) ? 0 : 1)
        radius: root.radius
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, IiStates.overlayOpen ? 0 : 1)
        border.width: 1

        layer.enabled: IiStates.overlayOpen
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: border.width
                height: border.height
                radius: root.radius
            }
        }

        ColumnLayout {
            id: contentColumn
            z: root.fancyBorders ? 0 : -1
            anchors.fill: parent
            spacing: 0

            // Title bar
            Rectangle {
                id: titleBar
                opacity: IiStates.overlayOpen ? 1 : 0
                Layout.fillWidth: true
                implicitWidth: titleBarRow.implicitWidth + root.padding * 2
                implicitHeight: titleBarRow.implicitHeight + root.padding * 2
                color: root.fancyBorders ? "transparent" : Appearance.colors.colLayer1Base
                // border.color: Appearance.colors.colOutlineVariant
                // border.width: 1
                
                RowLayout {
                    id: titleBarRow
                    anchors {
                        fill: parent
                        margins: root.padding
                    }
                    spacing: 2

                    MaterialSymbol {
                        text: root.materialSymbol
                        Layout.leftMargin: 6
                        iconSize: 20
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                    }
                    
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        elide: Text.ElideRight
                    }

                    TitlebarButton {
                        visible: root.showCenterButton
                        materialSymbol: "recenter"
                        onClicked: root.center()
                        StyledToolTip {
                            text: "Center"
                        }
                    }

                    TitlebarButton {
                        visible: (root.pinned && root.showClickabilityButton)
                        materialSymbol: "mouse"
                        toggled: !root.clickthrough
                        onClicked: root.toggleClickthrough()
                        StyledToolTip {
                            text: "Clickable when pinned"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "keep"
                        toggled: root.pinned
                        onClicked: root.togglePinned()
                        StyledToolTip {
                            text: "Pin"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "close"
                        onClicked: root.close()
                        StyledToolTip {
                            text: "Close"
                        }
                    }
                }
            }

            // Content
            Item {
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: root.fancyBorders ? root.padding : 0
                Layout.topMargin: -border.border.width // Border of a rectangle is drawn inside its bounds, so we do this to make the gap not too big
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                implicitWidth: Math.max(root.persistentStateEntry.width, root.minimumWidth)
                implicitHeight: Math.max(root.persistentStateEntry.height, root.minimumHeight)
                children: [root.contentItem]
            }
        }
    }


    component TitlebarButton: RippleButton {
        id: titlebarButton
        required property string materialSymbol
        buttonRadius: height / 2
        implicitHeight: contentItem.implicitHeight
        implicitWidth: implicitHeight
        padding: 0

        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            anchors.centerIn: parent
            implicitWidth: 30
            implicitHeight: 30

            MaterialSymbol {
                id: iconWidget
                anchors.centerIn: parent
                iconSize: 20
                text: titlebarButton.materialSymbol
                fill: titlebarButton.toggled
                color: titlebarButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
