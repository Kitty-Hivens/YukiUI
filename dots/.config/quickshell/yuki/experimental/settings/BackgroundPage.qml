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
    readonly property string thumbnails: `${FileUtils.trimFileProtocol(String(Directories.genericCache))}/thumbnails/large`
    readonly property var pictureExtensions: ["jpg", "jpeg", "png", "webp", "avif", "bmp", "svg", "gif"]
    readonly property var videoExtensions: ["mp4", "webm", "mkv", "avi", "mov"]

    function extensionOf(path: string): string {
        const name = path.slice(path.lastIndexOf("/") + 1);
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    }

    // The folder's pictures and videos. Folders inside it are not wallpapers
    // and were drawn as empty tiles.
    readonly property var shown: Wallpapers.wallpapers.filter(path => {
        const extension = root.extensionOf(path);
        return root.pictureExtensions.includes(extension) || root.videoExtensions.includes(extension);
    })

    // The thumbnail freedesktop keeps for a file, the one file managers and
    // the other environments' pickers read and write.
    function thumbnailOf(path: string): string {
        return `${root.thumbnails}/${Qt.md5(FileUtils.fileUrl(path))}.png`;
    }

    Component.onCompleted: {
        Wallpapers.load();
        // Ones missing are made in the background, and a tile shows the
        // picture itself until its thumbnail is there.
        Wallpapers.generateThumbnail("large");
    }

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
                source: FileUtils.fileUrl(root.current)
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
            description: Translation.tr("%1 pictures").arg(root.shown.length)

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
                model: root.shown

                AbstractButton {
                    id: tile

                    required property string modelData
                    readonly property bool current: tile.modelData === root.current
                    readonly property bool video: root.videoExtensions.includes(root.extensionOf(tile.modelData))
                    // Decoding a whole 4K original for every tile on every
                    // visit is what this saves. A missing thumbnail falls back
                    // to the original, scaled as it is read.
                    property bool thumbnailMissing: false
                    // Made while the page was open, so tried again.
                    Connections {
                        target: Wallpapers
                        function onThumbnailGeneratedFile(filePath) {
                            if (filePath === tile.modelData)
                                tile.thumbnailMissing = false;
                        }
                        function onThumbnailGenerated() {
                            tile.thumbnailMissing = false;
                        }
                    }

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
                            source: !tile.thumbnailMissing ? FileUtils.fileUrl(root.thumbnailOf(tile.modelData))
                                : tile.video ? "" : FileUtils.fileUrl(tile.modelData)
                            sourceSize: Qt.size(360, 203)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: {
                                if (status === Image.Error && !tile.thumbnailMissing)
                                    tile.thumbnailMissing = true;
                            }
                        }
                        ExGlyph {
                            anchors.centerIn: parent
                            visible: tile.video
                            text: "movie"
                            size: 28
                            color: "#ffffff"
                            style: Text.Outline
                            styleColor: "#80000000"
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
