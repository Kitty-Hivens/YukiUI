pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell.Widgets

import qs.core
import qs.core.functions
import qs.core.services
import qs.experimental.looks

// The picture behind the windows: the one there now, the others in the
// wallpaper folder to pick from, and any picture on disk. Picking one goes
// through the wallpaper switcher, so the shell's colours follow.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property string current: FileUtils.trimFileProtocol(String(Config.options.background.wallpaperPath))

    Component.onCompleted: Wallpapers.load()

    spacing: ExLooks.spacing.s

    FileDialog {
        id: picker
        title: Translation.tr("Choose a picture")
        nameFilters: [`${Translation.tr("Pictures")} (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.gif)`]
        onAccepted: Wallpapers.select(FileUtils.trimFileProtocol(picker.selectedFile.toString()))
    }
    FolderDialog {
        id: folderPicker
        title: Translation.tr("Choose a folder")
        onAccepted: Wallpapers.setDirectory(FileUtils.trimFileProtocol(folderPicker.selectedFolder.toString()))
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: ExLooks.spacing.m
        spacing: ExLooks.spacing.l

        ClippingRectangle {
            Layout.preferredWidth: 352
            Layout.preferredHeight: 198
            radius: ExLooks.radius.card
            color: ExLooks.colors.surfaceSunken

            Image {
                anchors.fill: parent
                source: Config.options.background.wallpaperPath
                sourceSize: Qt.size(704, 396)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 4

            ExText {
                Layout.fillWidth: true
                text: root.current.split("/").pop()
                role: "label"
                elide: Text.ElideMiddle
            }
            ExText {
                Layout.fillWidth: true
                text: root.current.slice(0, root.current.lastIndexOf("/"))
                dim: true
                elide: Text.ElideMiddle
            }
            ExButton {
                Layout.topMargin: ExLooks.spacing.m
                kind: "control"
                glyph: "shuffle"
                text: Translation.tr("Random from the folder")
                enabled: Wallpapers.wallpapers.length > 1
                onClicked: Wallpapers.randomFromCurrentFolder()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Pictures in the folder")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "folder"
            text: Wallpapers.effectiveDirectory
            description: Translation.tr("%1 pictures").arg(Wallpapers.wallpapers.length)

            ExButton {
                kind: "control"
                text: Translation.tr("Change folder")
                onClicked: folderPicker.open()
            }
            ExButton {
                kind: "tonal"
                text: Translation.tr("Choose a picture")
                onClicked: picker.open()
            }
        }

        // Every picture in the folder, the one in use marked.
        Flow {
            id: gallery

            readonly property int columns: Math.max(2, Math.floor((width + spacing) / (180 + spacing)))
            readonly property real tile: (width - (columns - 1) * spacing) / columns

            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.s
            spacing: ExLooks.spacing.s

            Repeater {
                model: Wallpapers.wallpapers

                AbstractButton {
                    id: tile

                    required property string modelData
                    readonly property bool current: tile.modelData === root.current

                    width: gallery.tile
                    height: gallery.tile * 9 / 16
                    hoverEnabled: true
                    onClicked: Wallpapers.select(tile.modelData)

                    background: ClippingRectangle {
                        radius: ExLooks.radius.control
                        color: ExLooks.colors.surfaceSunken

                        Image {
                            anchors.fill: parent
                            anchors.margins: tile.current ? 3 : 0
                            source: `file://${tile.modelData}`
                            sourceSize: Qt.size(360, 203)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: ExLooks.radius.control
                            color: "transparent"
                            border.width: tile.current ? 3 : (tile.hovered ? 1 : 0)
                            border.color: tile.current ? ExLooks.colors.accent : ExLooks.colors.border
                        }
                    }
                }
            }
        }
    }
}
