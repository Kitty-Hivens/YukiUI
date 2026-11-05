pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// What the file picked is: a look at it where one can be had, a picture, a frame
// of a video or the start of a text, and the facts about it. Everything is read
// for the file on show only, and an answer for one picked before it is dropped.
Rectangle {
    id: root

    /** The picker's way of naming kinds and drawing icons, sizes and dates. */
    required property var picker
    /** The one thing selected, or empty. */
    property string path: ""
    property bool isDir: false
    property int selectedCount: 0

    readonly property string name: root.path.slice(root.path.lastIndexOf("/") + 1)
    readonly property string extension: root.picker.extensionOf(root.name)
    readonly property string kind: root.path.length === 0 || root.isDir ? "" : root.picker.mimeIconName(root.name)
    readonly property bool isPicture: root.kind === "image-x-generic"
    readonly property bool isVideo: root.kind === "video-x-generic"
    readonly property bool isText: root.kind === "text-x-generic" || root.kind === "text-x-script"

    readonly property string kindText: {
        if (root.isDir)
            return Translation.tr("File folder");
        const word = root.isPicture ? Translation.tr("Picture")
            : root.isVideo ? Translation.tr("Video")
            : root.isText ? Translation.tr("Text")
            : root.kind === "audio-x-generic" ? Translation.tr("Audio")
            : root.kind === "application-x-archive" ? Translation.tr("Archive")
            : root.kind === "application-pdf" ? Translation.tr("Document")
            : root.kind === "application-x-executable" ? Translation.tr("Program")
            : Translation.tr("File");
        return root.extension.length > 0 ? `${word}  ·  ${root.extension.toUpperCase()}` : word;
    }

    // What was read, for the path it was read for.
    property string readPath: ""
    property string sizeText: ""
    property string modifiedText: ""
    property string dimensionsText: ""
    property string textStart: ""
    property string videoFrame: ""
    readonly property bool current: root.readPath === root.path

    // Moving down a list with the keys passes many files on the way.
    onPathChanged: reading.restart()
    Timer {
        id: reading
        interval: 120
        onTriggered: {
            root.dimensionsText = "";
            root.textStart = "";
            root.videoFrame = "";
            root.sizeText = "";
            root.modifiedText = "";
            root.readPath = root.path;
            if (root.path.length === 0)
                return;
            facts.running = false;
            facts.running = true;
            if (root.isPicture) {
                dimensions.running = false;
                dimensions.running = true;
            } else if (root.isText) {
                textReader.running = false;
                textReader.running = true;
            } else if (root.isVideo) {
                frameMaker.target = `${FileUtils.trimFileProtocol(String(Directories.genericCache))}/thumbnails/large/${Qt.md5(FileUtils.fileUrl(root.path))}.png`;
                frameMaker.running = false;
                frameMaker.running = true;
            }
        }
    }

    Process {
        id: facts
        command: ["stat", "--format=%s\t%Y", "--", root.readPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\t");
                if (parts.length < 2)
                    return;
                if (!root.isDir)
                    root.sizeText = root.picker.humanSize(Number(parts[0]));
                const time = Config.options.time;
                root.modifiedText = Qt.locale().toString(new Date(Number(parts[1]) * 1000), `${time.dateWithYearFormat} ${time.format}`);
            }
        }
    }
    Process {
        id: dimensions
        // The first frame only: a long animation would be read through otherwise.
        command: ["magick", "identify", "-format", "%w × %h", `${root.readPath}[0]`]
        stdout: StdioCollector {
            onStreamFinished: root.dimensionsText = text.trim()
        }
    }
    Process {
        id: textReader
        command: ["head", "--bytes=4096", "--", root.readPath]
        stdout: StdioCollector {
            // A name can lie: something holding a nul is not text to show.
            onStreamFinished: root.textStart = text.includes("\0") ? "" : text
        }
    }
    Process {
        id: frameMaker
        property string target: ""
        // The cache the file manager keeps, so a frame made once is there next time.
        command: ["sh", "-c", "[ -s \"$2\" ] || { mkdir -p \"$(dirname \"$2\")\" && ffmpegthumbnailer -i \"$1\" -o \"$2\" -s 512 -q 6; } 2>/dev/null; [ -s \"$2\" ] && echo \"$2\"", "yuki-video-frame", root.readPath, frameMaker.target]
        stdout: StdioCollector {
            onStreamFinished: root.videoFrame = text.trim()
        }
    }

    readonly property string imageSource: !root.current ? ""
        : root.isPicture ? FileUtils.fileUrl(root.path)
        : root.videoFrame.length > 0 ? FileUtils.fileUrl(root.videoFrame)
        : ""

    color: ExLooks.colors.surface

    ExText {
        anchors.centerIn: parent
        width: parent.width - 2 * ExLooks.spacing.xl
        visible: root.path.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.selectedCount > 1 ? Translation.tr("%1 selected").arg(root.selectedCount) : Translation.tr("Select a file to see it here")
        dim: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ExLooks.spacing.m
        visible: root.path.length > 0
        spacing: ExLooks.spacing.m

        Rectangle {
            Layout.fillWidth: true
            // A text gets the room it can use. A picture is seen in a band, so
            // the facts under it stay where they are from file to file.
            Layout.fillHeight: root.isText
            Layout.preferredHeight: root.isText ? -1 : 200
            radius: ExLooks.radius.control
            color: ExLooks.colors.surfaceSunken
            clip: true

            Image {
                id: look
                anchors.fill: parent
                anchors.margins: ExLooks.spacing.s
                visible: status === Image.Ready
                source: root.imageSource
                sourceSize: Qt.size(560, 400)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }
            ExGlyph {
                anchors.centerIn: parent
                visible: root.isVideo && look.visible
                text: "play_circle"
                size: 40
                fill: 1
                color: "#ffffff"
                style: Text.Outline
                styleColor: "#80000000"
            }
            ExText {
                anchors.fill: parent
                anchors.margins: ExLooks.spacing.m
                visible: root.isText && root.textStart.length > 0
                text: root.textStart
                textFormat: Text.PlainText
                font.family: "monospace"
                font.pixelSize: 11
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                clip: true
                dim: true
            }
            // Anything there is no look at, or none yet.
            Image {
                anchors.centerIn: parent
                width: 72
                height: 72
                visible: !look.visible && !(root.isText && root.textStart.length > 0) && status === Image.Ready
                sourceSize: Qt.size(144, 144)
                asynchronous: true
                source: root.path.length > 0 ? `file://${root.picker.iconThemeRoots[0]}/${root.picker.iconRelative(root.name, root.isDir)}` : ""
            }
        }

        ExText {
            Layout.fillWidth: true
            text: root.name
            role: "label"
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.xs

            Repeater {
                model: [
                    { label: Translation.tr("Type"), value: root.kindText },
                    { label: Translation.tr("Size"), value: root.current ? root.sizeText : "" },
                    { label: Translation.tr("Dimensions"), value: root.current ? root.dimensionsText : "" },
                    { label: Translation.tr("Modified"), value: root.current ? root.modifiedText : "" }
                ].filter(fact => fact.value.length > 0)

                RowLayout {
                    id: fact

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: ExLooks.spacing.s

                    ExText {
                        text: fact.modelData.label
                        role: "caption"
                        dim: true
                    }
                    ExText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: fact.modelData.value
                        role: "caption"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item {
            visible: !root.isText
            Layout.fillHeight: true
        }
    }
}
