pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// Light or dark, and the picture behind the windows. Both go through the
// wallpaper switcher, so the shell and the applications follow at once.
WelcomeStep {
    id: root

    readonly property string current: FileUtils.trimFileProtocol(String(Config.options.background.wallpaperPath))
    readonly property string thumbnails: `${FileUtils.trimFileProtocol(String(Directories.genericCache))}/thumbnails/large`
    readonly property var pictureExtensions: ["jpg", "jpeg", "png", "webp", "avif", "bmp"]
    /** A few pictures of the folder to pick from here, the one in use first. */
    readonly property var offered: {
        const pictures = Wallpapers.wallpapers.filter(path => {
            const name = path.slice(path.lastIndexOf("/") + 1);
            const dot = name.lastIndexOf(".");
            return dot > 0 && root.pictureExtensions.includes(name.slice(dot + 1).toLowerCase());
        });
        const others = pictures.filter(path => path !== root.current);
        return [...(root.current.length > 0 ? [root.current] : []), ...others].slice(0, 6);
    }

    function setMode(dark: bool) {
        if (dark !== ExLooks.dark)
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"]);
    }
    function thumbnailOf(path: string): string {
        return `${root.thumbnails}/${Qt.md5(FileUtils.fileUrl(path))}.png`;
    }

    Component.onCompleted: {
        Wallpapers.load();
        Wallpapers.generateThumbnail("large");
    }

    title: Translation.tr("Light or dark")
    subtitle: Translation.tr("For the desktop and the applications at once, and the picture behind them. The colours of the shell follow the picture.")

    FileDialog {
        id: picker
        title: Translation.tr("Choose a picture")
        nameFilters: [`${Translation.tr("Pictures")} (*.png *.jpg *.jpeg *.webp *.avif *.bmp)`]
        onAccepted: Wallpapers.select(FileUtils.trimFileProtocol(picker.selectedFile.toString()))
    }

    // The two modes as small pictures of a window, as on the colours page.
    RowLayout {
        Layout.fillWidth: true
        spacing: ExLooks.spacing.m

        Repeater {
            model: [
                { dark: false, name: Translation.tr("Light"), paper: "#eef0f4", card: "#ffffff", ink: "#15161a", accent: "#4f6bed" },
                { dark: true, name: Translation.tr("Dark"), paper: "#1b1c21", card: "#26272d", ink: "#e9eaf0", accent: "#6179f2" }
            ]

            AbstractButton {
                id: mode

                ExPrimaryOnly {
                    z: 1
                }

                required property var modelData
                readonly property bool chosen: mode.modelData.dark === ExLooks.dark

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 150
                hoverEnabled: true
                onClicked: root.setMode(mode.modelData.dark)

                ExFocusRing {
                    cornerRadius: ExLooks.settings.plateRadius
                }

                background: Rectangle {
                    radius: ExLooks.settings.plateRadius
                    color: ExLooks.settings.plate
                    border.width: mode.chosen ? 2 : 0
                    border.color: ExLooks.colors.accent

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: mode.hovered
                        pressed: mode.down
                    }
                }
                contentItem: ColumnLayout {
                    spacing: ExLooks.spacing.m

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: ExLooks.spacing.m
                        Layout.bottomMargin: 0
                        radius: ExLooks.radius.control
                        color: mode.modelData.paper

                        Rectangle {
                            x: 14
                            y: 14
                            width: parent.width * 0.58
                            height: parent.height - 28
                            radius: 8
                            color: mode.modelData.card

                            Column {
                                x: 12
                                y: 12
                                spacing: 6

                                Rectangle {
                                    width: 56
                                    height: 7
                                    radius: 3.5
                                    color: mode.modelData.ink
                                    opacity: 0.8
                                }
                                Rectangle {
                                    width: 84
                                    height: 5
                                    radius: 2.5
                                    color: mode.modelData.ink
                                    opacity: 0.35
                                }
                                Rectangle {
                                    width: 36
                                    height: 12
                                    radius: 6
                                    color: mode.modelData.accent
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.leftMargin: ExLooks.spacing.m
                        Layout.bottomMargin: ExLooks.spacing.m
                        spacing: ExLooks.spacing.s

                        ExGlyph {
                            text: mode.chosen ? "radio_button_checked" : "radio_button_unchecked"
                            size: 18
                            color: mode.chosen ? ExLooks.colors.accent : ExLooks.colors.textDim
                        }
                        ExText {
                            text: mode.modelData.name
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Background")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "wallpaper"
            text: root.current.length > 0 ? root.current.split("/").pop() : Translation.tr("No picture yet")
            description: Wallpapers.effectiveDirectory

            ExButton {
                kind: "control"
                glyph: "shuffle"
                text: Translation.tr("Random")
                visible: Wallpapers.wallpapers.length > 1
                onClicked: Wallpapers.randomFromCurrentFolder()
            }
            ExButton {
                kind: "tonal"
                text: Translation.tr("Choose a picture")
                onClicked: picker.open()
            }
        }

        // A few of the folder's pictures, the one in use marked. Hidden for a
        // folder with nothing else in it, which on a fresh install it is.
        Flow {
            id: strip

            readonly property int columns: 6
            readonly property real tile: Math.floor((width - (strip.columns - 1) * spacing) / strip.columns)

            Layout.fillWidth: true
            visible: root.offered.length > 1
            spacing: ExLooks.spacing.s

            Repeater {
                model: root.offered

                AbstractButton {
                    id: tile

                    ExPrimaryOnly {
                        z: 1
                    }

                    required property string modelData
                    readonly property bool chosen: tile.modelData === root.current
                    property bool thumbnailMissing: false

                    width: strip.tile
                    height: Math.round(strip.tile * 9 / 16)
                    hoverEnabled: true
                    onClicked: Wallpapers.select(tile.modelData)

                    Connections {
                        target: Wallpapers
                        function onThumbnailGenerated() {
                            tile.thumbnailMissing = false;
                        }
                    }

                    ExFocusRing {}

                    background: Rectangle {
                        radius: ExLooks.radius.control
                        color: ExLooks.settings.sunken

                        Image {
                            anchors.fill: parent
                            source: !tile.thumbnailMissing ? FileUtils.fileUrl(root.thumbnailOf(tile.modelData)) : FileUtils.fileUrl(tile.modelData)
                            sourceSize: Qt.size(320, 180)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: {
                                if (status === Image.Error && !tile.thumbnailMissing)
                                    tile.thumbnailMissing = true;
                            }
                        }
                        WelcomeCorners {
                            color: ExLooks.settings.plate
                            radius: ExLooks.radius.control
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: ExLooks.radius.control
                            color: "transparent"
                            border.width: tile.chosen ? 3 : (tile.hovered ? 1 : 0)
                            border.color: tile.chosen ? ExLooks.colors.accent : ExLooks.colors.border
                        }
                    }
                }
            }
        }
    }
}
