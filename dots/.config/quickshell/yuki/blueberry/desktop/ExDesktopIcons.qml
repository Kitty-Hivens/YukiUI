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
import qs.blueberry.looks

// What lies in the desktop folder, as icons on the wallpaper, the way Windows
// keeps them: each in a cell of a grid clear of the dock, and staying in its
// cell until moved, so one going away leaves a gap rather than shifting the
// rest. A new one takes the first free cell, counting down the columns from
// the top left. Sorting lays them all out again in order.
//
// A click picks one, Ctrl adds to the pick, a drag over the empty desktop picks
// everything it crosses. What is picked is dragged together to other cells, or
// into a folder dropped on. A double click opens, a right click offers what can
// be done, and once the desktop is clicked the keys work on it: Delete, Enter,
// F2, Ctrl+A, Escape and the arrows, and Ctrl+C, Ctrl+X and Ctrl+V, which copy,
// cut and paste files the way the file manager does, to and from it. A name is
// changed in place, under its icon, as Windows does it, and something new is
// made where the desktop was right clicked and named there at once.
//
// Drawn in the background layer's own window, so the icons stay under every
// window. Their menu is a window of its own over everything.
Item {
    id: root

    required property var screenModel

    readonly property string folder: StandardPaths.standardLocations(StandardPaths.DesktopLocation)[0] ?? ""
    readonly property string folderPath: FileUtils.trimFileProtocol(String(root.folder))

    readonly property var options: Config.options.blueberry.desktop
    // The three sizes Windows offers, each with a cell to match.
    readonly property real iconSize: root.options.iconSize === "small" ? 32 : root.options.iconSize === "large" ? 72 : 48
    readonly property real cellWidth: root.options.iconSize === "small" ? 76 : root.options.iconSize === "large" ? 112 : 84
    readonly property real cellHeight: root.iconSize + 48

    // Kept clear of the dock, which lies over this window.
    readonly property string dockEdge: Config.options.blueberry.dock.edge
    readonly property real dockRoom: ExLooks.dock.thickness + (Config.options.blueberry.dock.style !== "attached" ? ExLooks.dock.floatingGap : 0) + ExLooks.spacing.s
    readonly property rect area: Qt.rect(
        ExLooks.spacing.s + (root.dockEdge === "left" ? root.dockRoom : 0),
        ExLooks.spacing.s + (root.dockEdge === "top" ? root.dockRoom : 0),
        root.width - 2 * ExLooks.spacing.s - (root.dockEdge === "left" || root.dockEdge === "right" ? root.dockRoom : 0),
        root.height - 2 * ExLooks.spacing.s - (root.dockEdge === "top" || root.dockEdge === "bottom" ? root.dockRoom : 0))
    readonly property int rows: Math.max(1, Math.floor(root.area.height / root.cellHeight))
    readonly property int columns: Math.max(1, Math.floor(root.area.width / root.cellWidth))

    /**
     * The keys are wanted while the desktop was the last thing clicked, picked
     * or not, as on Windows: a paste goes to the empty desktop. Wanted for as
     * long as something was picked, a pointer merely passing over the empty
     * desktop took the keyboard from the window being typed into: the
     * compositor hands it to a layer that asks for it on demand as the
     * pointer goes by.
     */
    property bool clickedLast: false
    // And while a name is being typed, for as long as it is.
    readonly property bool wantsKeys: root.clickedLast || root.renaming.length > 0
    /**
     * Asking on demand does not take the keyboard until the pointer moves, so
     * a key pressed right after the click reached the window from before, a
     * Delete among them. For a moment after a click the keys are asked for
     * outright, which takes them at once, and then on demand, which keeps them.
     */
    property bool seizing: false
    readonly property bool windowActive: root.Window.active
    onWindowActiveChanged: {
        if (!root.windowActive && !root.seizing) {
            root.clickedLast = false;
            // Another window taken up keeps the name typed, as a click
            // elsewhere does.
            root.commitRename();
        }
    }

    function clicked() {
        root.forceActiveFocus();
        root.clickedLast = true;
    }

    /**
     * Lets go of the keys, before something is opened in a window of its own.
     * Held by the desktop, they kept the window that opened from having them,
     * so it could not be closed from the keyboard until it was clicked.
     */
    function letGoKeys() {
        root.commitRename();
        root.clickedLast = false;
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
        onTriggered: {
            root.seizing = false;
            // Focus lost while the keys were being seized was not acted on
            // then, so it is now.
            if (!root.windowActive)
                root.clickedLast = false;
        }
    }

    /** Paths picked, as keys of an object for a quick look-up. */
    property var picked: ({})
    /** The icon the arrows move on from. */
    property string cursorName: ""
    property point bandStart: Qt.point(0, 0)
    property point bandEnd: Qt.point(0, 0)
    property bool banding: false
    /** What was picked before a band drawn with Ctrl, which the band adds to. */
    property var bandBase: []
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
        // Not before the window has its size: on a grid of one cell every
        // name was given that cell, and kept it.
        if (!root.placesRead || root.awaitingSort || root.width <= 0 || root.height <= 0)
            return;
        let changed = false;
        const next = Object.assign({}, root.places);
        for (const name of root.names) {
            const cell = root.layout[name];
            if (!cell)
                continue;
            const kept = next[name];
            // A cell on the grid that another name holds was lost to it, and
            // the one this name was given instead is the one to keep. A cell
            // off the grid is kept for when the grid is large enough again.
            const lost = kept && kept[0] < root.columns && kept[1] < root.rows && (kept[0] !== cell[0] || kept[1] !== cell[1]);
            if (kept === undefined || lost) {
                next[name] = cell;
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

    /**
     * A new sorting asked for and not delivered yet.
     *
     * The folder is sorted again on a thread of its own and the new order
     * arrives later. Laid out at once, the icons took their cells in the old
     * order and kept them, so the new one never showed until "Arrange icons".
     */
    property bool awaitingSort: false

    Connections {
        target: root.options
        function onSortByChanged() {
            root.awaitingSort = true;
            root.places = {};
            sortTimeout.restart();
        }
    }

    // In case the new order never announces itself.
    Timer {
        id: sortTimeout
        interval: 2000
        onTriggered: {
            if (!root.awaitingSort)
                return;
            root.awaitingSort = false;
            root.refreshNames(false);
            root.arrange();
        }
    }

    function refreshNames(sorted: bool) {
        const out = [];
        for (let i = 0; i < files.count; i++)
            out.push(files.get(i, "fileName"));
        // One name gone and one come in the same change is a rename. The new
        // name keeps the old one's cell, and its pick, rather than moving to
        // the first free cell.
        const gone = root.names.filter(name => !out.includes(name));
        const added = out.filter(name => !root.names.includes(name));
        if (gone.length === 1 && added.length === 1 && !root.awaitingSort) {
            const [from, to] = [gone[0], added[0]];
            if (root.places[from] && !root.places[to]) {
                const next = Object.assign({}, root.places);
                next[to] = next[from];
                delete next[from];
                root.places = next;
                saveLater.restart();
            }
            if (root.picked[root.pathOf(from)]) {
                const picked = Object.assign({}, root.picked);
                delete picked[root.pathOf(from)];
                picked[root.pathOf(to)] = true;
                root.picked = picked;
            }
            if (root.cursorName === from)
                root.cursorName = to;
        }
        // A name being changed that went away meanwhile is not changed.
        if (root.renaming.length > 0 && !out.includes(root.renaming))
            root.renaming = "";
        // Something just made is named as soon as it is there.
        if (root.renameWhenListed.length > 0 && out.includes(root.renameWhenListed)) {
            const made = root.renameWhenListed;
            root.renameWhenListed = "";
            Qt.callLater(() => root.startRename(made));
        }
        if (sorted && root.awaitingSort) {
            root.awaitingSort = false;
            sortTimeout.stop();
            root.places = {};
        }
        root.names = out;
        if (!root.awaitingSort)
            Qt.callLater(root.keepNewPlaces);
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
        onTriggered: root.savePlaces()
    }

    function savePlaces() {
        const kept = {};
        for (const name of root.names)
            if (root.places[name])
                kept[name] = root.places[name];
        placesView.setText(JSON.stringify({ places: kept }, null, 2));
    }

    // Moved to another screen, this one is torn down, and a move made just
    // before would otherwise be lost with it.
    Component.onDestruction: {
        if (saveLater.running)
            root.savePlaces();
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
    /**
     * The press the drag belongs to, and the only one whose release drops it.
     * A file coming or going rebuilds the icons from the first one that moved,
     * the one held among them, and a release then never arrived: the drag
     * stayed up, and the next plain click anywhere dropped it, into whatever
     * folder it had last been over.
     */
    property var dragOwner: null

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
        root.dragOwner = null;
        root.dragging = false;
        root.dragDelta = Qt.point(0, 0);
        root.dragLead = "";
        root.dropFolder = "";
    }

    function drop() {
        const paths = root.pickedPaths();
        if (root.dropFolder.length > 0) {
            root.runFileJob(["gio", "move", ...paths, root.dropFolder], Translation.tr("Could not move"));
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

    /**
     * Launchers allowed to run: those with the executable bit, as GNOME and KDE
     * ask of one outside the system's own folders. Anything else on the desktop
     * can carry a Name and an Icon of its choosing, so a downloaded
     * "invoice.pdf.desktop" drew itself as a PDF and ran its command on a
     * double click. One not allowed shows as the file it is and opens as text.
     */
    property var trusted: ({})

    function setTrusted(path: string, yes: bool) {
        if ((root.trusted[path] === true) === yes)
            return;
        const next = Object.assign({}, root.trusted);
        next[path] = yes;
        root.trusted = next;
    }

    function isRunnable(path: string): bool {
        return path.endsWith(".desktop") && root.trusted[path] === true;
    }

    function allowLaunching(paths) {
        root.runFileJob(["chmod", "u+x", ...paths], Translation.tr("Could not allow launching"), () => {
            for (const path of paths)
                root.setTrusted(path, true);
        });
    }

    function open(path: string) {
        root.letGoKeys();
        // A launcher allowed to run is run, anything else goes to what opens it.
        // Allowed is asked again at the moment of running: what was known came
        // from when the icon was made, and a launcher written over since under
        // the same name, without the bit, would have run on that.
        if (root.isRunnable(path))
            Quickshell.execDetached(["sh", "-c", 'if [ -x "$1" ]; then exec gio launch "$1"; else exec xdg-open "$1"; fi', "yuki-desktop-open", path]);
        else
            Quickshell.execDetached(["xdg-open", path]);
    }

    function openAll(paths) {
        for (const path of paths)
            root.open(path);
    }

    function openPicked() {
        root.openAll(root.pickedPaths());
    }

    function trash(paths) {
        if (paths.length === 0)
            return;
        root.runFileJob(["gio", "trash", ...paths], Translation.tr("Could not move to the trash"));
        root.pick([]);
    }

    function trashPicked() {
        root.trash(root.pickedPaths());
    }

    // --- Naming -------------------------------------------------------------

    /** The name being changed in place, or empty. */
    property string renaming: ""
    /** Something just made, whose name is changed as soon as it is listed. */
    property string renameWhenListed: ""
    /** What the field under the icon holds, kept here so it is read whichever way the change ends. */
    property string renameText: ""

    function startRename(name: string) {
        if (!root.names.includes(name))
            return;
        root.pick([root.pathOf(name)]);
        root.cursorName = name;
        root.renameText = name;
        root.clickedLast = true;
        // Taken outright, as after a click: the menu it was asked for from
        // had the pointer, and the keys would otherwise wait for it to move.
        root.seizeKeys();
        root.renaming = name;
    }

    /** Ends the change, giving the file the name typed when `keep`. */
    function finishRename(keep: bool) {
        const name = root.renaming;
        if (name.length === 0)
            return;
        const wanted = root.renameText.trim();
        root.renaming = "";
        root.forceActiveFocus();
        if (!keep || wanted.length === 0 || wanted === name)
            return;
        root.runFileJob(["gio", "rename", root.pathOf(name), wanted], Translation.tr("Could not rename"));
    }

    function commitRename() {
        root.finishRename(true);
    }

    /**
     * What else can be made, as the file managers offer it: the files in the
     * templates folder, as Nautilus has them, and the templates Dolphin
     * lists in the data directories. Each { kind, name, icon, path }.
     */
    property var templates: []

    function readTemplates() {
        if (!templateReader.running)
            templateReader.running = true;
    }

    Process {
        id: templateReader

        command: ["bash", Quickshell.shellPath("scripts/files/templates.sh"), (Translation.languageCode || "").split("_")[0]]
        stdout: StdioCollector {
            id: templateList
            onStreamFinished: {
                const found = [];
                for (const line of templateList.text.split("\n")) {
                    const fields = line.split("\t");
                    if (fields.length !== 4 || (fields[0] !== "file" && fields[0] !== "link") || fields[1].length === 0 || fields[3].length === 0)
                        continue;
                    found.push({ kind: fields[0], name: fields[1], icon: fields[2] === "-" ? "" : fields[2], path: fields[3] });
                }
                root.templates = found;
            }
        }
    }
    Component.onCompleted: root.readTemplates()

    /** The name a template is offered under: its file's without the extension, or the one it gives, without its trailing dots. */
    function templateName(template): string {
        if (template.kind === "file") {
            const dot = template.name.lastIndexOf(".");
            return dot > 0 ? template.name.slice(0, dot) : template.name;
        }
        return template.name.replace(/[\s.\u2026]+$/, "");
    }

    /** A name not yet taken on the desktop: the one asked for, or it numbered. */
    function freeName(base: string, extension: string): string {
        let name = base + extension;
        for (let n = 2; root.names.includes(name); n++)
            name = `${base} ${n}${extension}`;
        return name;
    }

    /**
     * Makes something new where the desktop was right clicked, in the free
     * cell nearest it, and names it there once it is listed.
     */
    function create(folder: bool, at: point) {
        const name = folder ? root.freeName(Translation.tr("New folder"), "") : root.freeName(Translation.tr("New text document"), ".txt");
        root.placeNew(name, at);
        // Never over something already there, should it appear meanwhile.
        if (folder)
            root.runFileJob(["mkdir", "--", root.pathOf(name)], Translation.tr("Could not make the folder"));
        else
            root.runFileJob(["sh", "-c", 'set -C; : > "$1"', "yuki-desktop-new", root.pathOf(name)], Translation.tr("Could not make the document"));
    }

    /** A copy of a template, made and named as anything new is. */
    function createFrom(template, at: point) {
        const file = template.path.split("/").pop();
        const dot = file.lastIndexOf(".");
        const extension = dot > 0 ? file.slice(dot) : "";
        const name = root.freeName(root.templateName(template), extension);
        root.placeNew(name, at);
        root.runFileJob(["cp", "-n", "--", template.path, root.pathOf(name)], Translation.tr("Could not make the document"));
    }

    /** Gives a name about to be made the free cell nearest a point, and has it named once it is there. */
    function placeNew(name: string, at: point) {
        const taken = {};
        for (const other of root.names)
            taken[`${root.layout[other][0]},${root.layout[other][1]}`] = true;
        const column = Math.max(0, Math.min(root.columns - 1, Math.floor((at.x - root.area.x) / root.cellWidth)));
        const row = Math.max(0, Math.min(root.rows - 1, Math.floor((at.y - root.area.y) / root.cellHeight)));
        const next = Object.assign({}, root.places);
        next[name] = root.nearestFree(column, row, taken);
        root.places = next;
        root.renameWhenListed = name;
    }

    // --- The clipboard ------------------------------------------------------

    /** What was cut and not pasted yet, drawn faded, as Windows draws it. */
    property var cutPaths: ({})
    /** The text the last copy or cut put on the clipboard, to tell when something else has been copied since. */
    property string offeredText: ""

    /** On the clipboard as files, as the file manager puts them: copied, or cut to be moved. */
    function offer(paths, cut: bool) {
        if (paths.length === 0)
            return;
        const marks = {};
        if (cut)
            for (const path of paths)
                marks[path] = true;
        root.cutPaths = marks;
        root.offeredText = paths.join("\n");
        Quickshell.execDetached(["bash", Directories.clipboardOfferScriptPath, ...(cut ? ["--cut"] : []), "--", ...paths]);
    }

    // Anything copied since, here or elsewhere, ends a cut: its files are no
    // longer the ones on the clipboard.
    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            if (Quickshell.clipboardText !== root.offeredText)
                root.cutPaths = {};
        }
    }

    /** What is on the clipboard, into the desktop folder, and picked as it lands. */
    function paste() {
        if (pasteJob.running)
            return;
        pasteJob.running = true;
    }

    Process {
        id: pasteJob

        command: ["bash", Directories.clipboardPasteScriptPath, root.folderPath, Translation.tr("copy")]
        stdout: StdioCollector {
            id: pasted
            onStreamFinished: {
                const names = pasted.text.split("\n").filter(name => name.length > 0);
                if (names.length > 0)
                    root.pick(names.map(name => root.pathOf(name)));
            }
        }
        stderr: StdioCollector {
            id: pasteErrors
        }
        // Nothing to paste is no failure.
        onExited: exitCode => {
            if (exitCode === 1)
                Quickshell.execDetached(["notify-send", "-a", Translation.tr("Desktop"), Translation.tr("Could not paste"), pasteErrors.text.trim()]);
            root.cutPaths = {};
        }
    }

    /**
     * Runs a command on files and says so when it fails: a name already taken
     * in the folder dropped on, or a filesystem with no trash, used to leave the
     * icon where it was with no word why.
     */
    function runFileJob(command, failure: string, done) {
        const job = fileJob.createObject(root, { command: command, failure: failure, done: done ?? null });
        job.running = true;
    }

    Component {
        id: fileJob

        Process {
            id: job

            property string failure: ""
            property var done: null
            property int code: -1
            property bool streamDone: false

            function finish() {
                if (job.code < 0 || !job.streamDone)
                    return;
                if (job.code === 0)
                    job.done?.();
                else
                    Quickshell.execDetached(["notify-send", "-a", Translation.tr("Desktop"), job.failure, jobErrors.text.trim()]);
                job.destroy();
            }

            stderr: StdioCollector {
                id: jobErrors
                onStreamFinished: {
                    job.streamDone = true;
                    job.finish();
                }
            }
            onExited: exitCode => {
                job.code = exitCode;
                job.finish();
            }
        }
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
        } else if (event.key === Qt.Key_F2) {
            const paths = root.pickedPaths();
            if (paths.length === 1)
                root.startRename(paths[0].split("/").pop());
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.pick(root.names.map(name => root.pathOf(name)));
        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
            root.offer(root.pickedPaths(), false);
        } else if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
            root.offer(root.pickedPaths(), true);
        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            root.paste();
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

        onCountChanged: root.refreshNames(false)
        onStatusChanged: {
            if (files.status === FolderListModel.Ready)
                root.refreshNames(true);
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
            root.bandBase = root.pickedPaths();
            root.bandStart = Qt.point(event.x, event.y);
            root.bandEnd = root.bandStart;
            root.banding = true;
        }
        onPositionChanged: event => {
            if (!root.banding)
                return;
            root.bandEnd = Qt.point(event.x, event.y);
            const crossed = root.bandBase.slice();
            const band = root.band;
            for (let i = 0; i < icons.count; i++) {
                const icon = icons.itemAt(i);
                if (!icon)
                    continue;
                const cell = root.cellRectOf(icon.cell);
                if (cell.x < band.x + band.width && cell.x + cell.width > band.x && cell.y < band.y + band.height && cell.y + cell.height > band.y && !crossed.includes(icon.filePath))
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
            readonly property bool runnable: icon.isDesktopFile && root.trusted[icon.filePath] === true
            readonly property bool picked: root.picked[icon.filePath] === true
            readonly property bool cut: root.cutPaths[icon.filePath] === true
            readonly property bool moving: root.dragging && icon.picked
            readonly property bool dropTarget: root.dragging && root.dropFolder === icon.filePath
            // What a launcher calls itself and draws itself with, read off
            // the file, since it is not an installed application.
            property string launcherName: ""
            property string launcherIcon: ""
            readonly property string label: icon.runnable && icon.launcherName.length > 0 ? icon.launcherName
                : icon.runnable ? icon.fileName.slice(0, -".desktop".length)
                : icon.fileName

            readonly property bool renamingThis: root.renaming === icon.fileName
            readonly property var cell: root.layout[icon.fileName] ?? [0, 0]
            readonly property rect cellRect: root.cellRectOf(icon.cell)
            x: icon.cellRect.x + (icon.moving ? root.dragDelta.x : 0)
            y: icon.cellRect.y + (icon.moving ? root.dragDelta.y : 0)
            // A name being typed may run past the cell, over the neighbours.
            z: icon.moving || icon.renamingThis ? 2 : 1
            opacity: icon.moving ? 0.7 : icon.cut ? 0.5 : 1
            width: icon.cellRect.width
            height: icon.cellRect.height

            // Asked when the icon appears and whenever the launcher is read
            // again. "Allow launching" marks it allowed itself.
            // The path is the one asked about: by the time the answer comes the
            // icon can stand for another file, its rows having moved.
            Process {
                id: trustCheck
                property string asked: ""
                command: ["test", "-x", trustCheck.asked]
                onExited: exitCode => root.setTrusted(trustCheck.asked, exitCode === 0)
            }
            function checkTrust() {
                trustCheck.asked = icon.filePath;
                trustCheck.running = true;
            }
            Component.onCompleted: {
                if (icon.isDesktopFile)
                    icon.checkTrust();
            }

            FileView {
                id: launcherFile

                path: icon.isDesktopFile ? icon.filePath : ""
                // The roles of a delegate change one at a time when the rows
                // shift, so the path can name a file for a moment that is not
                // a launcher, or no longer there.
                printErrors: false
                onLoaded: {
                    icon.launcherIcon = "";
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
                    if (!trustCheck.running)
                        icon.checkTrust();
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
                        menu.showAt(mouse.pressAt.x, mouse.pressAt.y, { path: icon.filePath, isDir: icon.fileIsDir });
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
                        root.dragOwner = mouse;
                        root.dragLead = icon.fileName;
                    } else if (root.dragOwner !== mouse) {
                        return;
                    }
                    root.dragDelta = shift;
                    root.dropFolder = root.folderAt(point);
                }
                onReleased: event => {
                    if (root.dragging) {
                        if (root.dragOwner === mouse)
                            root.drop();
                        else
                            root.endDrag();
                        return;
                    }
                    if (event.button === Qt.LeftButton && mouse.wasPicked && !(event.modifiers & Qt.ControlModifier))
                        root.pick([icon.filePath]);
                    root.seizeKeys();
                }
                onCanceled: {
                    if (root.dragOwner === mouse)
                        root.endDrag();
                }
                // Rebuilt under the pointer while it was dragging: the drag
                // goes with it, and the icons go back where they stood.
                Component.onDestruction: {
                    if (root.dragOwner === mouse)
                        root.endDrag();
                }
                onDoubleClicked: event => {
                    if (event.button === Qt.LeftButton)
                        root.open(icon.filePath);
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
                    source: visible ? FileUtils.fileUrl(icon.filePath) : ""
                    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                // A launcher allowed to run its own icon.
                IconImage {
                    anchors.fill: parent
                    visible: icon.runnable
                    source: !icon.runnable ? ""
                        : icon.launcherIcon.startsWith("/") ? FileUtils.fileUrl(icon.launcherIcon)
                        : Quickshell.iconPath(icon.launcherIcon.length > 0 ? icon.launcherIcon : "application-x-executable", "application-x-executable")
                }
                // Anything else the picture the file manager draws for it.
                Image {
                    id: themeIcon
                    anchors.fill: parent
                    visible: !icon.runnable && !root.isPicture(icon.fileName) && status === Image.Ready
                    source: picture.attempt < root.iconThemeRoots.length && !icon.runnable && !root.isPicture(icon.fileName)
                        ? FileUtils.fileUrl(`${root.iconThemeRoots[picture.attempt]}/${picture.themed}`) : ""
                    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                    // At once: the folder's rows are made again whenever a file
                    // comes, goes or is renamed, and the size changes, and read
                    // in the background every icon went blank for a frame.
                    asynchronous: false
                    onStatusChanged: {
                        if (status === Image.Error)
                            picture.attempt++;
                    }
                }
                ExGlyph {
                    anchors.centerIn: parent
                    visible: !icon.runnable && !root.isPicture(icon.fileName) && themeIcon.status !== Image.Ready
                    text: icon.fileIsDir ? "folder" : "draft"
                    size: 44
                    fill: 1
                    color: "#ffffff"
                }
            }

            ExText {
                visible: !icon.renamingThis
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

            // The name being changed, in a field where the label was. The
            // part before the extension is picked, so typing replaces the name
            // and keeps what kind of file it is. Enter or a click elsewhere
            // keeps it, Escape leaves the name as it was.
            // As wide as what is typed, from a little wider than the icon to a
            // little past the cell, then onto further lines, as Windows grows
            // its own, and drawn as the house's fields are.
            Rectangle {
                visible: icon.renamingThis
                anchors.horizontalCenter: parent.horizontalCenter
                y: picture.y + picture.height + ExLooks.spacing.xs - 4
                width: Math.min(root.cellWidth + 24, Math.max(root.iconSize + 32, typed.advanceWidth + 24))
                height: renameField.contentHeight + 10

                TextMetrics {
                    id: typed
                    font: renameField.font
                    text: renameField.text
                }
                radius: 6
                color: ExLooks.colors.surfaceSunken
                border.width: 2
                border.color: ExLooks.colors.accent

                TextInput {
                    id: renameField

                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    wrapMode: TextInput.WrapAtWordBoundaryOrAnywhere
                    font.family: ExLooks.font.family
                    font.pixelSize: ExLooks.font.label
                    color: ExLooks.colors.text
                    selectionColor: ExLooks.colors.tonal
                    selectedTextColor: ExLooks.colors.tonalInk
                    horizontalAlignment: TextInput.AlignHCenter
                    clip: true
                    selectByMouse: true
                    onTextEdited: root.renameText = renameField.text
                    onAccepted: root.commitRename()
                    Keys.onEscapePressed: event => {
                        root.finishRename(false);
                        event.accepted = true;
                    }
                    onActiveFocusChanged: {
                        if (!renameField.activeFocus && icon.renamingThis)
                            root.commitRename();
                    }
                }

                onVisibleChanged: {
                    if (!visible)
                        return;
                    renameField.text = icon.fileName;
                    const dot = icon.fileIsDir ? -1 : icon.fileName.lastIndexOf(".");
                    renameField.select(0, dot > 0 ? dot : icon.fileName.length);
                    renameField.forceActiveFocus();
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
        /**
         * The part of the desktop's menu gone into: "view", "sort" or "new",
         * opening in place of the menu with a way back at its top, as the
         * other menus of this desktop go deeper. Empty at the top.
         */
        property string page: ""

        function showAt(x: real, y: real, target) {
            menu.target = target;
            menu.at = Qt.point(x, y);
            menu.page = "";
            menu.pageArrival = 1;
            menu.heldHeight = 0;
            menu.shown = true;
        }

        function close() {
            menu.shown = false;
        }

        function run(item) {
            menu.close();
            if (item.away)
                root.letGoKeys();
            item.run();
        }

        /**
         * From shut (0) to open (1), as the other menus come: quickly, a short
         * way and growing a little. Run from the first frame of the menu's
         * window, which comes a moment after the window, and back out before
         * the window goes.
         */
        property bool presented: false
        property real openness: menu.shown && menu.presented ? 1 : 0
        Behavior on openness {
            NumberAnimation {
                duration: menu.shown ? ExLooks.motion.normal : ExLooks.motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: menu.shown ? ExLooks.motion.enter : ExLooks.motion.exit
            }
        }

        /** A page coming in, from the right going deeper and from the left going back. */
        property real pageArrival: 1
        property int pageDirection: 1
        onPageChanged: {
            menu.pageDirection = menu.page.length > 0 ? 1 : -1;
            pageIn.restart();
        }
        NumberAnimation {
            id: pageIn
            target: menu
            property: "pageArrival"
            from: 0
            to: 1
            duration: ExLooks.motion.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ExLooks.motion.decelerate
        }

        /** The tallest the menu has been since it opened, which its window keeps. */
        property real heldHeight: 0

        /** One of a set of choices, ticked when it is the one in use. */
        function choice(text: string, chosen: bool, run): var {
            return { text: text, glyph: chosen ? "check" : "", run: run };
        }

        readonly property var items: {
            const target = menu.target;
            const options = root.options;
            const settings = page => () => Surfaces.open("settings", page);
            if (!target && menu.page === "view")
                return [
                    { back: true, text: Translation.tr("View"), glyph: "arrow_back" },
                    { separator: true },
                    menu.choice(Translation.tr("Large icons"), options.iconSize === "large", () => options.iconSize = "large"),
                    menu.choice(Translation.tr("Medium icons"), options.iconSize === "medium", () => options.iconSize = "medium"),
                    menu.choice(Translation.tr("Small icons"), options.iconSize === "small", () => options.iconSize = "small"),
                    { separator: true },
                    menu.choice(Translation.tr("Show desktop icons"), options.showIcons, () => options.showIcons = !options.showIcons)
                ];
            if (!target && menu.page === "new") {
                const list = [
                    { back: true, text: Translation.tr("New"), glyph: "arrow_back" },
                    { separator: true },
                    { text: Translation.tr("Folder"), glyph: "create_new_folder", run: () => root.create(true, menu.at) }
                ];
                // A text document of its own unless a template already makes one.
                if (!root.templates.some(template => template.path.toLowerCase().endsWith(".txt")))
                    list.push({ text: Translation.tr("Text document"), glyph: "note_add", run: () => root.create(false, menu.at) });
                if (root.templates.length > 0)
                    list.push({ separator: true });
                for (const template of root.templates)
                    list.push({
                        text: root.templateName(template),
                        glyph: "description",
                        iconSource: template.icon.length > 0 ? Quickshell.iconPath(template.icon, true) : "",
                        run: () => root.createFrom(template, menu.at)
                    });
                return list;
            }
            if (!target && menu.page === "sort")
                return [
                    { back: true, text: Translation.tr("Sort by"), glyph: "arrow_back" },
                    { separator: true },
                    menu.choice(Translation.tr("Name"), options.sortBy === "name", () => options.sortBy = "name"),
                    menu.choice(Translation.tr("Size"), options.sortBy === "size", () => options.sortBy = "size"),
                    menu.choice(Translation.tr("Type"), options.sortBy === "type", () => options.sortBy = "type"),
                    menu.choice(Translation.tr("Date modified"), options.sortBy === "date", () => options.sortBy = "date"),
                    { separator: true },
                    { text: Translation.tr("Arrange icons"), glyph: "grid_view", run: () => root.arrange() }
                ];
            if (!target)
                return [
                    { text: Translation.tr("View"), glyph: "visibility", page: "view" },
                    { text: Translation.tr("Sort by"), glyph: "sort", page: "sort" },
                    { separator: true },
                    { text: Translation.tr("Paste"), glyph: "content_paste", shortcut: "Ctrl+V", run: () => root.paste() },
                    { text: Translation.tr("New"), glyph: "add", page: "new" },
                    { separator: true },
                    { text: Translation.tr("Open in terminal"), glyph: "terminal", away: true, run: () => Quickshell.execDetached(["bash", "-c", `cd "$1" && exec ${Config.options.apps.terminal}`, "yuki-desktop-terminal", root.folderPath]) },
                    { text: Translation.tr("Open desktop folder"), glyph: "folder_open", away: true, run: () => Quickshell.execDetached(["xdg-open", root.folderPath]) },
                    { separator: true },
                    { text: Translation.tr("Background"), glyph: "wallpaper", away: true, run: settings("background") },
                    { text: Translation.tr("Display settings"), glyph: "desktop_windows", away: true, run: settings("display") },
                    { text: Translation.tr("Desktop settings"), glyph: "settings", away: true, run: settings("desktop") }
                ];
            // The same files the keys would act on: everything picked.
            const paths = root.pickedPaths().length > 0 ? root.pickedPaths() : [target.path];
            const untrusted = paths.filter(path => path.endsWith(".desktop") && !root.isRunnable(path));
            const list = [
                { text: Translation.tr("Open"), glyph: "open_in_new", shortcut: "Enter", run: () => root.openAll(paths) }
            ];
            if (untrusted.length > 0)
                list.push({ text: Translation.tr("Allow launching"), glyph: "verified_user", run: () => root.allowLaunching(untrusted) });
            if (paths.length === 1)
                list.push({ text: Translation.tr("Rename"), glyph: "edit", shortcut: "F2", run: () => root.startRename(paths[0].split("/").pop()) });
            list.push(
                { text: Translation.tr("Show in folder"), glyph: "folder_open", away: true, run: () => Quickshell.execDetached(["xdg-open", target.isDir ? target.path : root.folderPath]) },
                { separator: true },
                { text: Translation.tr("Cut"), glyph: "content_cut", shortcut: "Ctrl+X", run: () => root.offer(paths, true) },
                { text: Translation.tr("Copy"), glyph: "content_copy", shortcut: "Ctrl+C", run: () => root.offer(paths, false) },
                { text: Translation.tr("Copy location"), glyph: "link", run: () => Quickshell.clipboardText = paths.join("\n") },
                { separator: true },
                { text: Translation.tr("Move to trash"), glyph: "delete", shortcut: "Delete", destructive: true, run: () => root.trash(paths) }
            );
            return list;
        }

        Loader {
            active: menu.shown || menu.openness > 0
            onActiveChanged: {
                if (!active)
                    menu.presented = false;
            }

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
                // Placed by the tallest the menu has been, so it does not move
                // as its pages change.
                margins {
                    left: Math.max(0, Math.min(menu.at.x, root.width - menuPlane.width - ExLooks.spacing.s) - menuWindow.shadowRoom)
                    top: Math.max(0, Math.min(menu.at.y, root.height - menu.heldHeight - ExLooks.spacing.s) - menuWindow.shadowRoom)
                }
                implicitWidth: menuPlane.width + 2 * menuWindow.shadowRoom
                // As tall as the menu has been since it opened: a page that is
                // shorter shrinks inside it rather than the window changing
                // size under the pointer every frame.
                implicitHeight: menu.heldHeight + 2 * menuWindow.shadowRoom
                // Going, it takes no more clicks.
                mask: Region {
                    item: menu.shown ? menuPlane : nothing
                }
                Item {
                    id: nothing
                }

                // The frames are the Qt window's, under the layer.
                Connections {
                    target: menuPlane.Window.window
                    enabled: !menu.presented
                    function onFrameSwapped() {
                        menu.presented = true;
                    }
                }
                // Never left waiting for a frame that is not reported.
                Timer {
                    running: !menu.presented
                    interval: 300
                    onTriggered: menu.presented = true
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

                    readonly property real wanted: pageItems.implicitHeight + 2 * ExLooks.sizes.menuPadding
                    onWantedChanged: menu.heldHeight = Math.max(menu.heldHeight, menuPlane.wanted)
                    Component.onCompleted: menu.heldHeight = Math.max(menu.heldHeight, menuPlane.wanted)

                    implicitWidth: 280
                    height: menuPlane.wanted
                    Behavior on height {
                        enabled: menu.presented
                        NumberAnimation {
                            duration: ExLooks.motion.normal
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: ExLooks.motion.standard
                        }
                    }
                    x: menuWindow.shadowRoom
                    y: menuWindow.shadowRoom
                    opacity: Math.min(1, menu.openness * 1.8)
                    scale: 0.94 + 0.06 * menu.openness
                    transformOrigin: Item.TopLeft

                    // The page, cut to the plane as it grows or shrinks to it.
                    Item {
                        width: parent.width
                        height: menuPlane.height - 2 * ExLooks.sizes.menuPadding
                        clip: true

                    Column {
                        id: pageItems

                        width: parent.width
                        x: (1 - menu.pageArrival) * 24 * menu.pageDirection
                        opacity: menu.pageArrival

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
                                    iconSource: slot.modelData.iconSource ?? ""
                                    hasSubmenu: (slot.modelData.page ?? "").length > 0
                                    onClicked: {
                                        if (slot.modelData.page) {
                                            if (slot.modelData.page === "new")
                                                root.readTemplates();
                                            menu.page = slot.modelData.page;
                                        } else if (slot.modelData.back) {
                                            menu.page = "";
                                        } else {
                                            menu.run(slot.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                    }
                }
            }
        }
    }
}
