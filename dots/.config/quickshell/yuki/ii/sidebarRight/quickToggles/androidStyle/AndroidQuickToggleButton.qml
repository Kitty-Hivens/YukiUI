import QtQuick
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.core.models.quickToggles
import qs.core.functions
import qs.common.widgets
import qs.common

GroupButton {
    id: root
    
    // Info to be passed to by repeater. The type name is what identifies a tile
    // here: it is what the config keeps, and the one thing that stays the same
    // while rows are rebuilt around it.
    required property string buttonType
    required property bool expandedSize
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    // Signals
    signal openMenu()

    // Declared in specific toggles
    property QuickToggleModel toggleModel
    /// Nothing answers to this type: no branch of the panel, no plugin. Drawn all
    /// the same, so that it can be taken out of the panel again.
    property bool unknownType: false
    property string name: root.unknownType ? root.buttonType : (toggleModel?.name ?? "")
    property string statusText: root.unknownType ? Translation.tr("Unavailable")
        : ((toggleModel?.hasStatusText) ? (toggleModel?.statusText || (toggled ? Translation.tr("On") : Translation.tr("Off"))) : "")
    property string tooltipText: root.unknownType ? Translation.tr("%1 is not installed").arg(root.buttonType) : (toggleModel?.tooltipText ?? "")
    property string buttonIcon: root.unknownType ? "extension_off" : (toggleModel?.icon ?? "close")
    property bool available: root.unknownType ? false : (toggleModel?.available ?? true)
    toggled: toggleModel?.toggled ?? false
    property var mainAction: toggleModel?.mainAction ?? null
    altAction: toggleModel?.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)

    // Edit mode state
    property bool editMode: false

    // Sizing shenanigans
    baseWidth: root.baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    baseHeight: root.baseCellHeight
    enableImplicitWidthAnimation: !editMode && root.mouseArea.containsMouse
    enableImplicitHeightAnimation: !editMode && root.mouseArea.containsMouse
    Behavior on baseWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on baseHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    opacity: 0
    Component.onCompleted: {
        opacity = 1
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    enabled: available || editMode
    padding: 6
    horizontalPadding: padding
    verticalPadding: padding

    colBackground: Appearance.colors.colLayer2
    colBackgroundToggled: (altAction && expandedSize) ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary
    colBackgroundToggledHover: (altAction && expandedSize) ? Appearance.colors.colLayer2Hover : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: (altAction && expandedSize) ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive
    buttonRadius: toggled ? Appearance.rounding.large : height / 2
    buttonRadiusPressed: Appearance.rounding.normal
    property color colText: (toggled && !(altAction && expandedSize) && enabled) ? Appearance.colors.colOnPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer2, enabled ? 0 : 0.7)
    property color colIcon: expandedSize ? ((root.toggled) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3) : colText

    onClicked: {
        if (root.expandedSize && root.altAction) root.altAction();
        else if (root.mainAction) root.mainAction();
    }

    contentItem: RowLayout {
        id: contentItem
        spacing: 4
        anchors {
            centerIn: root.expandedSize ? undefined : parent
            fill: root.expandedSize ? parent : undefined
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }

        // Icon
        MouseArea {
            id: iconMouseArea
            hoverEnabled: true
            acceptedButtons: (root.expandedSize && root.altAction) ? Qt.LeftButton : Qt.NoButton
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.topMargin: root.verticalPadding
            Layout.bottomMargin: root.verticalPadding
            implicitHeight: iconBackground.implicitHeight
            implicitWidth: iconBackground.implicitWidth
            cursorShape: Qt.PointingHandCursor

            onClicked: if (root.mainAction) root.mainAction()

            Rectangle {
                id: iconBackground
                anchors.fill: parent
                implicitWidth: height
                radius: root.radius - root.verticalPadding
                color: {
                    const baseColor = root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    const transparentizeAmount = (root.altAction && root.expandedSize) ? 0 : 1
                    return ColorUtils.transparentize(baseColor, transparentizeAmount)
                }

                Behavior on radius {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: root.toggled ? 1 : 0
                    iconSize: root.expandedSize ? 22 : 24
                    color: root.colIcon
                    text: root.buttonIcon
                }

                // State layer
                Loader {
                    anchors.fill: parent
                    active: (root.expandedSize && root.altAction)
                    sourceComponent: Rectangle {
                        radius: iconBackground.radius
                        color: ColorUtils.transparentize(root.colIcon, iconMouseArea.containsPress ? 0.88 : iconMouseArea.containsMouse ? 0.95 : 1)
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        // Text column for expanded size
        Loader {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            visible: root.expandedSize
            active: visible
            sourceComponent: Column {
                spacing: -2

                StyledText {
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.name
                }

                StyledText {
                    visible: root.statusText
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font {
                        pixelSize: Appearance.font.pixelSize.smaller
                        weight: 100
                    }
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.statusText
                }
            }
        }
    }

    MouseArea { // Blocking MouseArea for edit interactions
        id: editModeInteraction
        visible: root.editMode
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons

        // The list is replaced rather than changed in place in all three of these.
        // Changing it in place does reach the file, but it signals every step on
        // the way: a two-step swap made the config hold one toggle twice, and the
        // panel rebuilt itself on that torn state before the second step landed --
        // a duplicate tile on screen, from a list that was never meant to have one.
        //
        // The position is looked up by type rather than by a place in the rows,
        // because rows skip empty entries and are laid out by tile size, so past
        // the first of either the two do not line up.
        function positionOf(toggleList, buttonType) {
            return toggleList.findIndex(toggle => toggle?.type === buttonType);
        }

        function toggleEnabled() {
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonType;
            const position = editModeInteraction.positionOf(toggleList, buttonType);
            Config.options.sidebar.quickToggles.android.toggles = (position === -1)
                ? toggleList.concat([{ type: buttonType, size: 1 }])
                : toggleList.filter((toggle, i) => i !== position);
        }

        function toggleSize() {
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonType;
            const position = editModeInteraction.positionOf(toggleList, buttonType);
            if (position === -1) return;
            Config.options.sidebar.quickToggles.android.toggles = toggleList.map((toggle, i) => (i === position)
                ? { type: toggle.type, size: 3 - toggle.size } // Alternate between 1 and 2
                : toggle);
        }

        function movePositionBy(offset) {
            const toggleList = Config.options.sidebar.quickToggles.android.toggles;
            const buttonType = root.buttonType;
            const position = editModeInteraction.positionOf(toggleList, buttonType);
            if (position === -1) return;
            const targetPosition = position + offset;
            if (targetPosition < 0 || targetPosition >= toggleList.length) return;
            const next = toggleList.slice();
            next[position] = toggleList[targetPosition];
            next[targetPosition] = toggleList[position];
            Config.options.sidebar.quickToggles.android.toggles = next;
        }

        onReleased: (event) => {
            if (event.button === Qt.LeftButton)
                toggleEnabled();
        }
        onPressed: (event) => {
            if (event.button === Qt.RightButton) toggleSize();
        }
        onPressAndHold: (event) => { // Also toggle size
            toggleSize();
        }
        onWheel: (event) => {
            if (event.angleDelta.y < 0) { // Move to right
                movePositionBy(1);
            } else if (event.angleDelta.y > 0) { // Move to left
                movePositionBy(-1);
            }
            event.accepted = true;
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.tooltipText !== ""
        text: root.tooltipText
    }
}
