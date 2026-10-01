pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core
import qs.core.functions
import qs.core.services
import qs.experimental.looks

// What lies in the desktop folder, as icons on the wallpaper, the way Windows
// keeps them: each in a cell of a grid clear of the dock, and staying in its
// cell until moved, so one going away leaves a gap rather than shifting the
// rest. A new one takes the first free cell, counting down the columns from
// the top left. Sorting lays them all out again in order.
//
// A click picks one, Ctrl adds to the pick, a drag over the empty desktop picks
// everything it crosses. What is picked is dragged together to other cells, or
// into a folder dropped on. A double click opens, a right click offers what can
// be done, and while something is picked the keys work on it: Delete, Enter,
// Ctrl+A, Escape and the arrows.
//
// Drawn in the background layer's own window, so the icons stay under every
// window. Their menu is a window of its own over everything.
Item {
    id: root

    required property var screenModel

    readonly property string folder: StandardPaths.standardLocations(StandardPaths.DesktopLocation)[0] ?? ""
    readonly property string folderPath: FileUtils.trimFileProtocol(String(root.folder))

    readonly property var options: Config.options.experimental.desktop
    // The three sizes Windows offers, each with a cell to match.
    readonly property real iconSize: root.options.iconSize === "small" ? 32 : root.options.iconSize === "large" ? 72 : 48
    readonly property real cellWidth: root.options.iconSize === "small" ? 76 : root.options.iconSize === "large" ? 112 : 84
    readonly property real cellHeight: root.iconSize + 48

    // Kept clear of the dock, which lies over this window.
    readonly property string dockEdge: Config.options.experimental.dock.edge
    readonly property real dockRoom: ExLooks.dock.thickness + (Config.options.experimental.dock.style !== "attached" ? ExLooks.dock.floatingGap : 0) + ExLooks.spacing.s
    readonly property rect area: Qt.rect(
        ExLooks.spacing.s + (root.dockEdge === "left" ? root.dockRoom : 0),
        ExLooks.spacing.s + (root.dockEdge === "top" ? root.dockRoom : 0),
        root.width - 2 * ExLooks.spacing.s - (root.dockEdge === "left" || root.dockEdge === "right" ? root.dockRoom : 0),
        root.height - 2 * ExLooks.spacing.s - (root.dockEdge === "top" || root.dockEdge === "bottom" ? root.dockRoom : 0))
    readonly property int rows: Math.max(1, Math.floor(root.area.height / root.cellHeight))
    readonly property int columns: Math.max(1, Math.floor(root.area.width / root.cellWidth))

    /**
     * The keys are wanted while something is picked and the desktop was the
     * last thing clicked. Wanted for as long as something is picked, a pointer
     * merely passing over the empty desktop took the keyboard from the window
     * being typed into: the compositor hands it to a layer that asks for it on
     * demand as the pointer goes by.
     */
    property bool clickedLast: false
    readonly property bool wantsKeys: root.clickedLast && Object.keys(root.picked).length > 0
    /**
     * Asking on demand does not take the keyboard until the pointer moves, so
     * a key pressed right after the click reached the window from before, a
     * Delete among them. For a moment after a click the keys are asked for
     * outright, which takes them at once, and then on demand, which keeps them.
     */
    property bool seizing: false
    readonly property bool windowActive: root.Window.active
    onWindowActiveChanged: {
        if (!root.windowActive && !root.seizing)
            root.clickedLast = false;
    }

    function clicked() {
        root.forceActiveFocus();
        root.clickedLast = true;
    }

    // On the release, not the press: changing how the keys are asked for in
    // the middle of a press makes the compositor call the press off, and a
    // drag with it.
    function seizeKeys() {
        root.seizing = true;
        seize.restart();
    }

    Timer {
        id: seize
        interval: 60
        onTriggered: root.seizing = false
    }

    /** Paths picked, as keys of an object for a quick look-up. */
    property var picked: ({})
    /** The icon the arrows move on from. */
    property string cursorName: ""
    property point bandStart: Qt.point(0, 0)
    property point bandEnd: Qt.point(0, 0)
    property bool banding: false
    readonly property rect band: Qt.rect(Math.min(root.bandStart.x, root.bandEnd.x), Math.min(root.bandStart.y, root.bandEnd.y),
        Math.abs(root.bandEnd.x - root.bandStart.x), Math.abs(root.bandEnd.y - root.bandStart.y))

    // --- Where each icon stands ---------------------------------------------

    /** The cell each name was put in, as [column, row], kept on disk. */
    property var places: ({})
    property bool placesRead: false
    /** The names in the folder, in the order the chosen sorting gives them. */
    property var names: []

    readonly property string placesFile: `${FileUtils.trimFileProtocol(String(Directories.state))}/user/desktop-icons.json`

    /**
     * Every name's cell. A name keeps the cell it was given while that cell is
     * on the grid and not claimed first by another. The rest, new ones among
     * them, take the free cells in order down the columns.
     */
    readonly property var layout: {
        const cells = {};
        const taken = {};
        const later = [];
        for (const name of root.names) {
            const place = root.places[name];
            const key = place ? `${place[0]},${place[1]}` : "";
            if (place && place[0] < root.columns && place[1] < root.rows && !taken[key]) {
                cells[name] = place;
                taken[key] = true;
            } else {
                later.push(name);
            }
        }
        let next = 0;
        const total = root.columns * root.rows;
        for (const name of later) {
            while (next < total && taken[`${Math.floor(next / root.rows)},${next % root.rows}`])
                next++;
            // A desktop fuller than the grid stacks what is left in the last cell.
            const cell = next < total ? [Math.floor(next / root.rows), next % root.rows] : [root.columns - 1, root.rows - 1];
            cells[name] = cell;
            taken[`${cell[0]},${cell[1]}`] = true;
        }
        return cells;
    }

    // A name given a cell for the first time keeps it from then on, so a gap
    // opening before it later does not pull it along.
    onLayoutChanged: Qt.callLater(root.keepNewPlaces)

    function keepNewPlaces() {
        if (!root.placesRead)
            return;
        let changed = false;
        const next = Object.assign({}, root.places);
        for (const name of root.names) {
            if (next[name] === undefined && root.layout[name]) {
                next[name] = root.layout[name];
                changed = true;
            }
        }
        if (changed) {
            root.places = next;
            saveLater.restart();
        }
    }

    /** Lays everything out again in the order of the sorting chosen. */
    function arrange() {
        root.places = {};
        Qt.callLater(root.keepNewPlaces);
    }

    Connections {
        target: root.options
        function onSortByChanged() {
            root.arrange();
        }
    }

    function refreshNames() {
        const out = [];
        for (let i = 0; i < files.count; i++)
            out.push(files.get(i, "fileName"));
        root.names = out;
    }

    function cellRectOf(cell): rect {
        return Qt.rect(root.area.x + cell[0] * root.cellWidth, root.area.y + cell[1] * root.cellHeight, root.cellWidth, root.cellHeight);
    }

    /** The free cell nearest to one asked for, in rings around it. */
    function nearestFree(column: int, row: int, taken): var {
        const reach = Math.max(root.columns, root.rows);
        for (let ring = 0; ring <= reach; ring++) {
            let best = null;
            let bestDistance = Infinity;
            for (let dc = -ring; dc <= ring; dc++) {
                for (let dr = -ring; dr <= ring; dr++) {
                    if (Math.max(Math.abs(dc), Math.abs(dr)) !== ring)
                        continue;
                    const c = column + dc;
                    const r = row + dr;
                    if (c < 0 || r < 0 || c >= root.columns || r >= root.rows || taken[`${c},${r}`])
                        continue;
                    const distance = dc * dc + dr * dr;
                    if (distance < bestDistance) {
                        best = [c, r];
                        bestDistance = distance;
                    }
                }
            }
            if (best)
                return best;
        }
        return [column, row];
    }

    FileView {
        id: placesView

        path: root.placesFile
        printErrors: false
        onLoaded: {
            try {
                root.places = JSON.parse(placesView.text()).places ?? {};
            } catch (error) {
                root.places = {};
            }
            root.placesRead = true;
            Qt.callLater(root.keepNewPlaces);
        }
        onLoadFailed: {
            root.placesRead = true;
            Qt.callLater(root.keepNewPlaces);
        }
    }

    // Written a moment after the last change, and only for names still there.
    Timer {
        id: saveLater
        interval: 400
        onTriggered: {
            const kept = {};
            for (const name of root.names)
                if (root.places[name])
                    kept[name] = root.places[name];
            placesView.setText(JSON.stringify({ places: kept }, null, 2));
        }
    }

    // --- Picking ------------------------------------------------------------

    function pick(paths) {
        const next = {};
        for (const path of paths)
            next[path] = true;
        root.picked = next;
    }

    function togglePick(path: string) {
        const next = Object.assign({}, root.picked);
        if (next[path])
            delete next[path];
        else
            next[path] = true;
        root.picked = next;
    }

    function pickedPaths(): var {
        return Object.keys(root.picked);
    }

    function pathOf(name: string): string {
        return `${root.folderPath}/${name}`;
    }

    // --- Dragging -----------------------------------------------------------

    property bool dragging: false
    property point dragDelta: Qt.point(0, 0)
    /** The icon taken hold of, the one that lands where the pointer lets go. */
    property string dragLead: ""
    /** A folder on the desktop the picked icons are over, to be moved into. */
    property string dropFolder: ""

    /** The folder icon under a point, other than the ones being dragged. */
    function folderAt(point: point): string {
        for (let i = 0; i < icons.count; i++) {
            const icon = icons.itemAt(i);
            if (!icon || !icon.fileIsDir || root.picked[icon.filePath])
                continue;
            const cell = root.cellRectOf(icon.cell);
            if (point.x >= cell.x && point.x < cell.x + cell.width && point.y >= cell.y && point.y < cell.y + cell.height)
                return icon.filePath;
        }
        return "";
    }

    function endDrag() {
        root.dragging = false;
        root.dragDelta = Qt.point(0, 0);
        root.dragLead = "";
        root.dropFolder = "";
    }

    function drop() {
        const paths = root.pickedPaths();
        if (root.dropFolder.length > 0) {
            Quickshell.execDetached(["gio", "move", ...paths, root.dropFolder]);
            root.pick([]);
            root.endDrag();
            return;
        }
        const columnShift = Math.round(root.dragDelta.x / root.cellWidth);
        const rowShift = Math.round(root.dragDelta.y / root.cellHeight);
        if (columnShift === 0 && rowShift === 0) {
            root.endDrag();
            return;
        }
        const moving = paths.map(path => path.split("/").pop()).filter(name => root.layout[name]);
        const taken = {};
        for (const name of root.names)
            if (!moving.includes(name))
                taken[`${root.layout[name][0]},${root.layout[name][1]}`] = true;
        // The one taken hold of first, so it lands where the pointer let go and
        // the others fit round it.
        const order = [root.dragLead, ...moving.filter(name => name !== root.dragLead)].filter(name => moving.includes(name));
        const next = Object.assign({}, root.places);
        for (const name of order) {
            const from = root.layout[name];
            const column = Math.max(0, Math.min(root.columns - 1, from[0] + columnShift));
            const row = Math.max(0, Math.min(root.rows - 1, from[1] + rowShift));
            const cell = root.nearestFree(column, row, taken);
            taken[`${cell[0]},${cell[1]}`] = true;
            next[name] = cell;
        }
        root.places = next;
        saveLater.restart();
        root.endDrag();
    }

    // --- Doing things -------------------------------------------------------

    function open(path: string, isDesktopFile: bool) {
        // A launcher on the desktop is run, anything else goes to what opens it.
        if (isDesktopFile)
            Quickshell.execDetached(["gio", "launch", path]);
        else
            Quickshell.execDetached(["xdg-open", path]);
    }

    function openPicked() {
        for (const path of root.pickedPaths())
            root.open(path, path.endsWith(".desktop"));
    }

    function trashPicked() {
        const paths = root.pickedPaths();
        if (paths.length === 0)
            return;
        Quickshell.execDetached(["gio", "trash", ...paths]);
        root.pick([]);
    }

    /** Moves the pick to the icon nearest the next cell that way. */
    function step(columnShift: int, rowShift: int) {
        const from = root.layout[root.cursorName] ?? null;
        if (!from) {
            const first = root.names.slice().sort((a, b) => root.layout[a][0] - root.layout[b][0] || root.layout[a][1] - root.layout[b][1])[0];
            if (first) {
                root.cursorName = first;
                root.pick([root.pathOf(first)]);
            }
            return;
        }
        // The nearest icon in that direction, counting cells.
        let best = "";
        let bestDistance = Infinity;
        for (const name of root.names) {
            const cell = root.layout[name];
            const dc = cell[0] - from[0];
            const dr = cell[1] - from[1];
            const ahead = columnShift !== 0 ? dc * columnShift > 0 : dr * rowShift > 0;
            if (!ahead)
                continue;
            const along = columnShift !== 0 ? Math.abs(dc) : Math.abs(dr);
            const across = columnShift !== 0 ? Math.abs(dr) : Math.abs(dc);
            const distance = along + across * 4;
            if (distance < bestDistance) {
                best = name;
                bestDistance = distance;
            }
        }
        if (best.length > 0) {
            root.cursorName = best;
            root.pick([root.pathOf(best)]);
        }
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Delete) {
            root.trashPicked();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.openPicked();
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.pick(root.names.map(name => root.pathOf(name)));
        } else if (event.key === Qt.Key_Escape) {
            root.pick([]);
        } else if (event.key === Qt.Key_Left) {
            root.step(-1, 0);
        } else if (event.key === Qt.Key_Right) {
            root.step(1, 0);
        } else if (event.key === Qt.Key_Up) {
            root.step(0, -1);
        } else if (event.key === Qt.Key_Down) {
            root.step(0, 1);
        } else {
            return;
        }
        event.accepted = true;
    }

    function extensionOf(name: string): string {
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    }

    function isPicture(name: string): bool {
        return ["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "svg"].includes(root.extensionOf(name));
    }

    function mimeIconName(name: string): string {
        const extension = root.extensionOf(name);
        if (extension === "pdf")
            return "application-pdf";
        if (["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "zst"].includes(extension))
            return "application-x-archive";
        if (["mp3", "ogg", "wav", "flac", "m4a", "opus"].includes(extension))
            return "audio-x-generic";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(extension))
            return "video-x-generic";
        if (["exe", "msi", "lnk"].includes(extension))
            return "application-x-executable";
        if (["txt", "md", "log", "csv", "json"].includes(extension))
            return "text-x-generic";
        if (["sh", "py", "js", "lua", "qml"].includes(extension))
            return "text-x-script";
        return "application-x-generic";
    }

    readonly property var iconThemeRoots: [
        `${FileUtils.trimFileProtocol(String(Directories.home))}/.local/share/icons/Material-Originals/scalable`,
        "/usr/share/icons/Material-Originals/scalable"
    ]

    FolderListModel {
        id: files

        folder: root.folder
        showDirs: true
        showDirsFirst: true
        showHidden: false
        showDotAndDotDot: false
        sortField: {
            switch (root.options.sortBy) {
            case "size":
                return FolderListModel.Size;
            case "type":
                return FolderListModel.Type;
            case "date":
                return FolderListModel.Time;
            }
            return FolderListModel.Name;
        }
        caseSensitive: false

        onCountChanged: root.refreshNames()
        onStatusChanged: {
            if (files.status === FolderListModel.Ready)
                root.refreshNames();
        }
    }

    // The empty desktop: a click lets go of what was picked, a drag picks, a
    // right click offers the desktop's own menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: event => {
            root.clicked();
            if (event.button === Qt.RightButton) {
                root.pick([]);
                menu.showAt(event.x, event.y, null);
                return;
            }
            menu.close();
            if (!(event.modifiers & Qt.ControlModifier))
                root.pick([]);
            root.bandStart = Qt.point(event.x, event.y);
            root.bandEnd = root.bandStart;
            root.banding = true;
        }
        onPositionChanged: event => {
            if (!root.banding)
                return;
            root.bandEnd = Qt.point(event.x, event.y);
            const crossed = [];
            const band = root.band;
            for (let i = 0; i < icons.count; i++) {
                const icon = icons.itemAt(i);
                if (!icon)
                    continue;
                const cell = root.cellRectOf(icon.cell);
                if (cell.x < band.x + band.width && cell.x + cell.width > band.x && cell.y < band.y + band.height && cell.y + cell.height > band.y)
                    crossed.push(icon.filePath);
            }
            root.pick(crossed);
        }
        onReleased: {
            root.banding = false;
            root.seizeKeys();
        }
        onCanceled: root.banding = false
    }

    Repeater {
        id: icons

        model: root.options.showIcons ? files : null

        Item {
            id: icon

            required property int index
            required property string fileName
            required property string filePath
            required property bool fileIsDir

            readonly property bool isDesktopFile: !icon.fileIsDir && icon.fileName.endsWith(".desktop")
            readonly property bool picked: root.picked[icon.filePath] === true
            readonly property bool moving: root.dragging && icon.picked
            readonly property bool dropTarget: root.dragging && root.dropFolder === icon.filePath
            // What a launcher calls itself and draws itself with, read off
            // the file, since it is not an installed application.
            property string launcherName: ""
            property string launcherIcon: ""
            readonly property string label: icon.isDesktopFile && icon.launcherName.length > 0 ? icon.launcherName
                : icon.isDesktopFile ? icon.fileName.slice(0, -".desktop".length)
                : icon.fileName

            readonly property var cell: root.layout[icon.fileName] ?? [0, 0]
            readonly property rect cellRect: root.cellRectOf(icon.cell)
            x: icon.cellRect.x + (icon.moving ? root.dragDelta.x : 0)
            y: icon.cellRect.y + (icon.moving ? root.dragDelta.y : 0)
            z: icon.moving ? 2 : 1
            opacity: icon.moving ? 0.7 : 1
            width: icon.cellRect.width
            height: icon.cellRect.height

            FileView {
                id: launcherFile

                path: icon.isDesktopFile ? icon.filePath : ""
                onLoaded: {
                    let inEntry = false;
                    const language = (Translation.languageCode || "").split("_")[0];
                    let name = "";
                    let localName = "";
                    for (const line of launcherFile.text().split("\n")) {
                        const trimmed = line.trim();
                        if (trimmed.startsWith("[")) {
                            inEntry = trimmed === "[Desktop Entry]";
                            continue;
                        }
                        if (!inEntry)
                            continue;
                        if (trimmed.startsWith("Name="))
                            name = trimmed.slice(5);
                        else if (language.length > 0 && trimmed.startsWith(`Name[${language}]=`))
                            localName = trimmed.slice(trimmed.indexOf("=") + 1);
                        else if (trimmed.startsWith("Icon="))
                            icon.launcherIcon = trimmed.slice(5);
                    }
                    icon.launcherName = localName || name;
                }
            }

            MouseArea {
                id: mouse

                // Where the press was, in the desktop's coordinates, and whether
                // the icon was picked already: a click on one of several picked
                // keeps them all picked for a drag, and picks it alone if it
                // turns out to be only a click.
                property point pressAt: Qt.point(0, 0)
                property bool wasPicked: false

                anchors.fill: parent
                anchors.margins: 2
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onPressed: event => {
                    root.clicked();
                    menu.close();
                    root.cursorName = icon.fileName;
                    mouse.pressAt = mouse.mapToItem(root, event.x, event.y);
                    mouse.wasPicked = icon.picked;
                    if (event.button === Qt.RightButton) {
                        if (!icon.picked)
                            root.pick([icon.filePath]);
                        menu.showAt(mouse.pressAt.x, mouse.pressAt.y, { path: icon.filePath, isDir: icon.fileIsDir, isDesktopFile: icon.isDesktopFile });
                    } else if (event.modifiers & Qt.ControlModifier) {
                        root.togglePick(icon.filePath);
                    } else if (!icon.picked) {
                        root.pick([icon.filePath]);
                    }
                }
                onPositionChanged: event => {
                    if (!(mouse.pressedButtons & Qt.LeftButton) || !icon.picked)
                        return;
                    const point = mouse.mapToItem(root, event.x, event.y);
                    const shift = Qt.point(point.x - mouse.pressAt.x, point.y - mouse.pressAt.y);
                    if (!root.dragging) {
                        if (Math.abs(shift.x) + Math.abs(shift.y) < 8)
                            return;
                        root.dragging = true;
                        root.dragLead = icon.fileName;
                    }
                    root.dragDelta = shift;
                    root.dropFolder = root.folderAt(point);
                }
                onReleased: event => {
                    if (root.dragging) {
                        root.drop();
                        return;
                    }
                    if (event.button === Qt.LeftButton && mouse.wasPicked && !(event.modifiers & Qt.ControlModifier))
                        root.pick([icon.filePath]);
                    root.seizeKeys();
                }
                onCanceled: root.endDrag()
                onDoubleClicked: event => {
                    if (event.button === Qt.LeftButton)
                        root.open(icon.filePath, icon.isDesktopFile);
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: ExLooks.radius.menuItem
                color: icon.dropTarget ? Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.5)
                    : icon.picked ? Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.35)
                    : mouse.containsMouse ? "#26ffffff" : "transparent"
                border.width: icon.picked || icon.dropTarget ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.45)
            }

            Item {
                id: picture

                anchors.horizontalCenter: parent.horizontalCenter
                y: ExLooks.spacing.s
                width: root.iconSize
                height: root.iconSize

                property int attempt: 0
                readonly property string themed: icon.fileIsDir ? "places/folder.svg" : `mimetypes/${root.mimeIconName(icon.fileName)}.svg`

                // A picture shows itself.
                Image {
                    anchors.fill: parent
                    visible: root.isPicture(icon.fileName)
                    source: visible ? `file://${icon.filePath}` : ""
                    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                // A launcher its own icon.
                IconImage {
                    anchors.fill: parent
                    visible: icon.isDesktopFile
                    source: !icon.isDesktopFile ? ""
                        : icon.launcherIcon.startsWith("/") ? `file://${icon.launcherIcon}`
                        : Quickshell.iconPath(icon.launcherIcon.length > 0 ? icon.launcherIcon : "application-x-executable", "application-x-executable")
                }
                // Anything else the picture the file manager draws for it.
                Image {
                    id: themeIcon
                    anchors.fill: parent
                    visible: !icon.isDesktopFile && !root.isPicture(icon.fileName) && status === Image.Ready
                    source: picture.attempt < root.iconThemeRoots.length && !icon.isDesktopFile && !root.isPicture(icon.fileName)
                        ? `file://${root.iconThemeRoots[picture.attempt]}/${picture.themed}` : ""
                    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                    asynchronous: true
                    onStatusChanged: {
                        if (status === Image.Error)
                            picture.attempt++;
                    }
                }
                ExGlyph {
                    anchors.centerIn: parent
                    visible: !icon.isDesktopFile && !root.isPicture(icon.fileName) && themeIcon.status !== Image.Ready
                    text: icon.fileIsDir ? "folder" : "draft"
                    size: 44
                    fill: 1
                    color: "#ffffff"
                }
            }

            ExText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: picture.y + picture.height + ExLooks.spacing.xs
                width: parent.width - 8
                text: icon.label
                role: "caption"
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#c0000000"
                    shadowBlur: 0.35
                    shadowVerticalOffset: 1
                    shadowHorizontalOffset: 0
                }
            }
        }
    }

    // The band a drag draws. What it looks like is still to be settled.
    Rectangle {
        visible: root.banding && root.band.width > 2 && root.band.height > 2
        x: root.band.x
        y: root.band.y
        width: root.band.width
        height: root.band.height
        radius: 2
        color: Qt.rgba(ExLooks.colors.accent.r, ExLooks.colors.accent.g, ExLooks.colors.accent.b, 0.2)
        border.width: 1
        border.color: ExLooks.colors.accent
    }

    // The menu, over everything, at the point clicked.
    Scope {
        id: menu

        property var target: null
        property point at: Qt.point(0, 0)
        property bool shown: false

        function showAt(x: real, y: real, target) {
            menu.target = target;
            menu.at = Qt.point(x, y);
            menu.shown = true;
        }

        function close() {
            menu.shown = false;
        }

        function run(action) {
            menu.close();
            action();
        }

        readonly property var items: {
            const target = menu.target;
            if (!target)
                return [
                    { text: Translation.tr("Arrange icons"), glyph: "grid_view", run: () => root.arrange() },
                    { text: Translation.tr("Open desktop folder"), glyph: "folder_open", run: () => Quickshell.execDetached(["xdg-open", root.folderPath]) }
                ];
            const paths = root.pickedPaths().length > 0 ? root.pickedPaths() : [target.path];
            return [
                { text: Translation.tr("Open"), glyph: "open_in_new", shortcut: "Enter", run: () => root.open(target.path, target.isDesktopFile) },
                { text: Translation.tr("Show in folder"), glyph: "folder_open", run: () => Quickshell.execDetached(["xdg-open", target.isDir ? target.path : root.folderPath]) },
                { text: Translation.tr("Copy location"), glyph: "content_copy", run: () => Quickshell.clipboardText = paths.join("\n") },
                { separator: true },
                { text: Translation.tr("Move to trash"), glyph: "delete", shortcut: "Delete", destructive: true, run: () => Quickshell.execDetached(["gio", "trash", ...paths]) }
            ];
        }

        Loader {
            active: menu.shown

            sourceComponent: PanelWindow {
                id: menuWindow

                screen: root.screenModel
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:desktopMenu"
                WlrLayershell.layer: WlrLayer.Top
                anchors {
                    top: true
                    left: true
                }
                // The window is larger than the menu by room for its shadow.
                readonly property real shadowRoom: 24
                margins {
                    left: Math.max(0, Math.min(menu.at.x, root.width - menuPlane.width - ExLooks.spacing.s) - menuWindow.shadowRoom)
                    top: Math.max(0, Math.min(menu.at.y, root.height - menuPlane.height - ExLooks.spacing.s) - menuWindow.shadowRoom)
                }
                implicitWidth: menuPlane.width + 2 * menuWindow.shadowRoom
                implicitHeight: menuPlane.height + 2 * menuWindow.shadowRoom
                mask: Region {
                    item: menuPlane
                }

                // Closed by a press anywhere else, which still reaches what it
                // landed on. A grab stands in without the press-report plugin.
                // Armed a moment after showing, so the right click that opened
                // the menu, reported a little later, does not close it again.
                property bool armed: false

                Timer {
                    running: true
                    interval: 100
                    onTriggered: menuWindow.armed = true
                }

                Connections {
                    target: PointerPress
                    enabled: PointerPress.available && menuWindow.armed

                    function onPressed(kind, name) {
                        if (kind !== "layer" || name !== "quickshell:desktopMenu")
                            menu.close();
                    }
                }

                HyprlandFocusGrab {
                    active: !PointerPress.available
                    windows: [menuWindow]
                    onCleared: menu.close()
                }

                ExMenu {
                    id: menuPlane

                    implicitWidth: 280
                    x: menuWindow.shadowRoom
                    y: menuWindow.shadowRoom

                    Repeater {
                        model: menu.items

                        Loader {
                            id: slot

                            required property var modelData
                            width: parent.width
                            sourceComponent: slot.modelData.separator ? separatorItem : actionItem

                            Component {
                                id: separatorItem
                                ExMenuSeparator {}
                            }
                            Component {
                                id: actionItem
                                ExMenuItem {
                                    text: slot.modelData.text
                                    glyph: slot.modelData.glyph
                                    shortcut: slot.modelData.shortcut ?? ""
                                    destructive: slot.modelData.destructive ?? false
                                    onClicked: menu.run(slot.modelData.run)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
