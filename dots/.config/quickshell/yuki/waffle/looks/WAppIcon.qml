import QtQuick
import org.kde.kirigami as Kirigami
import qs.core.services
import qs.core

Kirigami.Icon {
    id: root
    required property string iconName
    property bool separateLightDark: false
    property bool tryCustomIcon: true
    
    property real implicitSize: 24
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    animated: true
    roundToIconSize: false
    // A picture a window gave itself comes as its file's url, which the
    // fallback, a name looked up in the theme, would not find.
    readonly property bool picture: root.iconName.startsWith("file://")
    fallback: root.picture ? "" : root.iconName
    source: root.picture ? root.iconName
        : tryCustomIcon ? `${Looks.iconsPath}/${root.iconName}${!root.separateLightDark ? "" : Looks.dark ? "-dark" : "-light"}.svg` : fallback

    color: Looks.colors.fg
}
