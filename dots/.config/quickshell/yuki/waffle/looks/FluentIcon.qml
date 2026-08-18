import QtQuick
import org.kde.kirigami as Kirigami
import qs.core
import qs.waffle.looks

Kirigami.Icon {
    id: root
    required property string icon
    property bool filled: false
    property alias monochrome: root.isMask
    // Should be 16, but it appears the icons have some padding,
    // Unlike the Windows-only Segoe UI icons, the open source FluentUI ones are hella small
    property int implicitSize: 20
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    /// Which of the published drawings to use. Fluent draws every size separately --
    /// 16 is not 24 shrunk, it carries a heavier stroke and less detail -- so the file
    /// is picked to match the size it will appear at instead of one being scaled to
    /// all of them. On a tie the larger drawing wins, having more to lose gracefully.
    readonly property int artSize: {
        const sizes = [12, 16, 20, 24, 28, 32, 48];
        let best = sizes[0];
        for (const size of sizes) {
            const closer = Math.abs(size - root.implicitSize) - Math.abs(best - root.implicitSize);
            if (closer < 0 || (closer === 0 && size > best))
                best = size;
        }
        return best;
    }

    source: icon === "" ? "" : `${Looks.iconsPath}/${root.artSize}/${root.icon}${filled ? "-filled" : ""}.svg`
    fallback: root.icon
    roundToIconSize: false
    color: Looks.colors.fg
    isMask: true
    animated: true
}
