pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.waffle.looks
import qs.waffle.bar.tray

/**
 * Draws the tray icon that is currently being carried.
 *
 * The bar is 48 tall and clips anything lifted above it, which is why the drag
 * there is otherwise pinned to one axis. This surface gives the icon somewhere to
 * be drawn, the way the widget board has the picker's window draw a card on its
 * way out of the picker.
 *
 * It is created once and kept, rather than appearing for the duration of a drag:
 * a window that is born and destroyed inside an interaction is the same shape as
 * the teardown that segfaulted the shell when the bar was made to unmap under
 * fullscreen windows, and that cause is still unknown.
 *
 * It takes no input at all -- the mask is empty, so presses reach the bar beneath
 * and the gesture is still driven by the button it started on. It shares the bar's
 * edge and width, so a point in the bar's coordinates is the same x here and a
 * fixed offset in y.
 */
PanelWindow {
    id: root

    readonly property bool barAtBottom: Config.options.waffles.bar.bottom
    /// How far above the bar an icon can be carried.
    readonly property int reach: 160

    WlrLayershell.namespace: "quickshell:trayDrag"
    // Above everything, because the icon has to be visible over the bar it came
    // from and over the hidden-icons flyout, which is a popup of the bar and so
    // draws above the bar's own layer whatever order they were created in.
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"

    anchors {
        left: true
        right: true
        bottom: root.barAtBottom
        top: !root.barAtBottom
    }
    implicitHeight: root.reach + Looks.sizes.barHeight

    // Nothing here is clickable.
    mask: Region {
        x: 0
        y: 0
        width: 0
        height: 0
    }

    /// Where the carried icon would land. Windows draws it as a hairline that stands
    /// taller than the bar and reaches above its top edge -- which is why it is drawn
    /// here and not in the bar, where it would be cut off. It appears at any gap,
    /// including before the first icon.
    Rectangle {
        visible: TrayDragState.insertX >= 0
        width: 1
        color: Looks.colors.fg
        x: TrayDragState.insertX
        y: root.barAtBottom ? root.reach - insertionOverhang : Looks.sizes.barHeight - insertionHeight + insertionOverhang
        height: insertionHeight
        /// It does not span the bar. Measured off a frame that carried the bar itself
        /// as a scale reference: about 40 tall in all, of which some 11 stands above
        /// the bar's top edge, so it stops well short of the bar's floor. Drawing it
        /// as bar-height-plus-overhang made it half again too long, which is what was
        /// wrong before rather than the overhang alone.
        readonly property int insertionHeight: 40
        readonly property int insertionOverhang: 11
    }

    /// The plate saying what the drop will do, above the icon rather than above the
    /// slot it came from -- it travels with the thing being carried, which is where
    /// Windows puts it. It is there for the whole gesture; only the glyph changes,
    /// and "nothing will happen" is one of the three glyphs rather than a change of
    /// cursor. That was read off the frames the wrong way round once already.
    Rectangle {
        id: plate
        // Not while the insertion line is up: the line already says what letting go
        // does, and Windows was not seen showing both at once. Inferred from frames
        // that show one or the other, not measured showing neither.
        visible: TrayDragState.active && TrayDragState.insertX < 0
        x: carried.x + (carried.width - plate.width) / 2
        y: carried.y - plate.height - 14
        implicitWidth: plateIcon.implicitWidth + 12
        implicitHeight: plateIcon.implicitHeight + 12
        radius: Looks.radius.medium
        color: Looks.colors.bg2
        border.width: 1
        border.color: Looks.colors.bg2Border

        FluentIcon {
            id: plateIcon
            anchors.centerIn: parent
            icon: TrayDragState.dropAction === "pin" ? "pin"
                : TrayDragState.dropAction === "unpin" ? "pin-off"
                : "prohibited"
            implicitSize: 18
        }
    }

    FluentIcon {
        id: carried
        // The window itself stays mapped for good. Toggling a layer window's
        // visibility is what crashed the shell earlier today, and this one is
        // transparent and takes no input, so there is nothing to gain by it.
        visible: TrayDragState.active
        x: TrayDragState.pointerX - TrayDragState.grabX
        y: (root.barAtBottom ? root.reach : 0) + TrayDragState.pointerY - TrayDragState.grabY
        implicitSize: 16
        // `icon` names one of the bundled Fluent svgs and is required; a tray item
        // brings its own image instead, so the name is empty and the source is set
        // straight over the binding that would have derived it. Same as the bar's
        // own icon buttons do.
        icon: ""
        // A tray icon is a picture of its own, not one of the monochrome Fluent
        // glyphs, so it must not be drawn as a mask in the foreground colour.
        monochrome: false
        source: TrayDragState.item?.icon ?? ""
    }
}
