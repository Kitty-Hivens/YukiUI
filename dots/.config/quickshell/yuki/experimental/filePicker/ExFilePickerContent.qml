pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions
import qs.core.models
import qs.core.services
import qs.experimental.looks

// What the file picker window holds: the way to a folder, the places to jump
// to, the folder itself as a list, and what to answer with.
FocusScope {
    id: root

    readonly property var request: FilePicker.request
    readonly property string mode: root.request.mode ?? "open"
    readonly property bool saving: root.mode === "save"
    /** Picking a folder rather than a file, which is also how a batch save asks where to put its files. */
    readonly property bool directory: root.request.directory ?? false
    readonly property bool multiple: root.request.multiple ?? false
    readonly property var filters: root.request.filters ?? []
    /** The filter on show, from the one the application asked for. */
    property int filterIndex: Math.max(0, Math.min(root.request.currentFilter ?? 0, root.filters.length - 1))

    readonly property string titleText: (root.request.title ?? "").length > 0 ? root.request.title
        : root.saving ? Translation.tr("Save file")
        : root.directory ? Translation.tr("Select folder")
        : Translation.tr("Open file")
    readonly property string acceptText: (root.request.acceptLabel ?? "").length > 0 ? root.request.acceptLabel
        : root.saving ? Translation.tr("Save")
        : root.directory ? Translation.tr("Select")
        : Translation.tr("Open")

    property bool showHidden: false
    property bool foldersFirst: true
    /** 0 by name, 1 by size, 2 by date. */
    property int sortColumn: 0
    property bool sortDescending: false

    // The selection, by url, and which of it are folders, since a folder is
    // answered differently from a file.
    property var selectedUrls: []
    property var selectedDirs: ({})
    /**
     * Where Shift extends a selection from, and the row the arrow keys move
     * from, by url like the selection. Kept as row numbers they went on
     * pointing at whatever had moved into those rows since, a download
     * finishing or a sort, and Enter answered with another file.
     */
    property string anchorUrl: ""
    property string cursorUrl: ""

    property bool searchOpen: false
    property bool pathOpen: false
    readonly property bool searching: root.searchOpen && searchField.text.length > 0

    // How far each folder was scrolled, so going back lands where it was left.
    property var scrollMemory: ({})
    property bool restoreScrollPending: false

    property var bookmarks: []

    readonly property real rowHeight: 40
    readonly property real sizeColumnWidth: 88
    readonly property real dateColumnWidth: 136

    readonly property string homePath: root.pathOf(Directories.home)
    readonly property string currentPath: root.pathOf(folderModel.folder)

    /** A local path from a file url, without the escaping a url needs. */
    function pathOf(url): string {
        const path = FileUtils.trimFileProtocol(String(url));
        try {
            return decodeURIComponent(path).replace(/(.)\/+$/, "$1");
        } catch (error) {
            return path;
        }
    }

    /** A file url for a local path, each part escaped, so a # or a space in a name survives. */
    function urlOf(path: string): string {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    /**
     * Hands the choice to the portal. The folder model spells a url the way it
     * is shown, letters outside ASCII left as they are, so every url is written
     * out again with each part escaped before it leaves.
     */
    function answer(urls) {
        FilePicker.submit(urls.map(url => root.urlOf(root.pathOf(url))), root.filters.length > 0 ? root.filterIndex : undefined);
    }

    function childPath(name: string): string {
        return root.currentPath === "/" ? `/${name}` : `${root.currentPath}/${name}`;
    }

    // An application may describe a filter by media type alone. The list can
    // only match names, so the common types are spelled out as extensions, and
    // a filter with a type not known here shows everything rather than hiding
    // files it was meant to allow.
    readonly property var mimeExtensions: ({
        "image/*": ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff", "ico", "jxl"],
        "audio/*": ["mp3", "ogg", "oga", "opus", "flac", "wav", "m4a", "aac", "wma", "mid"],
        "video/*": ["mp4", "m4v", "mkv", "webm", "mov", "avi", "mpg", "mpeg", "wmv", "flv", "3gp"],
        "text/*": ["txt", "md", "csv", "log", "json", "xml", "html", "htm", "css", "ini", "conf", "yaml", "yml", "toml"],
        "image/png": ["png"],
        "image/jpeg": ["jpg", "jpeg"],
        "image/gif": ["gif"],
        "image/webp": ["webp"],
        "image/bmp": ["bmp"],
        "image/svg+xml": ["svg"],
        "image/avif": ["avif"],
        "image/tiff": ["tif", "tiff"],
        "application/pdf": ["pdf"],
        "application/json": ["json"],
        "application/zip": ["zip"],
        "text/plain": ["txt"],
        "text/html": ["html", "htm"],
        "text/csv": ["csv"],
        "text/markdown": ["md"],
        "audio/mpeg": ["mp3"],
        "audio/ogg": ["ogg", "oga", "opus"],
        "audio/flac": ["flac"],
        "audio/wav": ["wav"],
        "video/mp4": ["mp4", "m4v"],
        "video/webm": ["webm"],
        "video/x-matroska": ["mkv"]
    })

    readonly property var namePatterns: {
        const filter = root.filters[root.filterIndex];
        if (!filter)
            return ["*"];
        const patterns = (filter.patterns ?? []).slice();
        for (const mime of filter.mimes ?? []) {
            const extensions = root.mimeExtensions[mime];
            if (!extensions)
                return ["*"];
            for (const extension of extensions)
                patterns.push(`*.${extension}`);
        }
        return patterns.length > 0 ? patterns : ["*"];
    }

    // The same patterns for search results, which come from find and not
    // from the folder model.
    readonly property var nameRegexes: root.namePatterns.map(pattern => root.globRegex(pattern))

    function globRegex(pattern: string): var {
        let source = "";
        let inClass = false;
        for (let i = 0; i < pattern.length; i++) {
            const ch = pattern[i];
            if (inClass) {
                if (ch === "]")
                    inClass = false;
                source += ch === "\\" ? "\\\\" : ch;
            } else if (ch === "*") {
                // Any letter, a newline included, as a glob takes it.
                source += "[\\s\\S]*";
            } else if (ch === "?") {
                source += "[\\s\\S]";
            } else if (ch === "[") {
                inClass = true;
                source += "[";
                if (pattern[i + 1] === "!") {
                    source += "^";
                    i++;
                }
            } else {
                source += ch.replace(/[.+^${}()|\\\/\]]/g, "\\$&");
            }
        }
        try {
            return new RegExp(`^${source}$`, "i");
        } catch (error) {
            return /^.*$/;
        }
    }

    function matchesFilter(name: string): bool {
        return root.nameRegexes.some(regex => regex.test(name));
    }

    function extensionOf(name: string): string {
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    }

    function mimeIconName(name: string): string {
        const extension = root.extensionOf(name);
        if (extension === "pdf")
            return "application-pdf";
        if (extension === "appimage")
            return "application-vnd.appimage";
        if (["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "zst", "lz", "lzma"].includes(extension))
            return "application-x-archive";
        if (["mp3", "ogg", "oga", "wav", "flac", "m4a", "opus", "aac", "mid", "wma"].includes(extension))
            return "audio-x-generic";
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "3gp"].includes(extension))
            return "video-x-generic";
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "ico", "tif", "tiff", "jxl"].includes(extension))
            return "image-x-generic";
        if (["exe", "bin", "run", "msi"].includes(extension))
            return "application-x-executable";
        if (["iso", "img", "dmg"].includes(extension))
            return "application-x-cd-image";
        if (["sh", "fish", "bash", "zsh", "py", "js", "ts", "lua", "qml", "c", "cpp", "cc", "h", "hpp", "rs", "go", "java", "kt", "rb", "pl"].includes(extension))
            return "text-x-script";
        if (["txt", "md", "rtf", "log", "csv", "json", "yaml", "yml", "toml", "xml", "html", "htm", "css", "ini", "conf"].includes(extension))
            return "text-x-generic";
        return "application-x-generic";
    }

    // The same pictures the file manager draws, looked up by file because a
    // lookup by name comes back blank from this theme. Installed per user on
    // some machines and system wide by the package, so both are tried.
    readonly property var iconThemeRoots: [
        `${root.homePath}/.local/share/icons/Material-Originals/scalable`,
        "/usr/share/icons/Material-Originals/scalable"
    ]

    function iconRelative(name: string, isDir: bool): string {
        return isDir ? "places/folder.svg" : `mimetypes/${root.mimeIconName(name)}.svg`;
    }

    /** Stands in when neither copy of the theme has a picture. */
    function glyphFor(name: string, isDir: bool): string {
        if (isDir)
            return "folder";
        const icon = root.mimeIconName(name);
        return icon === "image-x-generic" ? "image"
            : icon === "audio-x-generic" ? "music_note"
            : icon === "video-x-generic" ? "movie"
            : icon === "application-x-archive" ? "folder_zip"
            : icon === "application-pdf" ? "picture_as_pdf"
            : icon === "text-x-script" ? "code"
            : "draft";
    }

    function humanSize(bytes): string {
        if (bytes === undefined || bytes === null || bytes < 0)
            return "";
        const units = [Translation.tr("B"), Translation.tr("KB"), Translation.tr("MB"), Translation.tr("GB"), Translation.tr("TB")];
        let value = bytes;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        const digits = unit > 0 && value < 10 ? 1 : 0;
        return `${Number(value).toLocaleString(Qt.locale(), "f", digits)} ${units[unit]}`;
    }

    /** The time for today, the day for this year, the full date before that. */
    function shortDate(date): string {
        if (!date || typeof date.getTime !== "function" || isNaN(date.getTime()) || date.getTime() <= 0)
            return "";
        const now = new Date();
        if (date.toDateString() === now.toDateString())
            return Qt.locale().toString(date, Config.options?.time.format ?? "hh:mm");
        if (date.getFullYear() === now.getFullYear())
            return Qt.locale().toString(date, "d MMM");
        return Qt.locale().toString(date, "d MMM yyyy");
    }

    /** One row of whichever list is on screen, the folder or the search results, or null past its end. */
    function entryAt(index: int): var {
        if (index < 0 || index >= (root.searching ? searchResults.count : folderModel.count))
            return null;
        if (root.searching) {
            const found = searchResults.get(index);
            return { name: found.fileName, path: found.filePath, url: found.fileUrl, isDir: found.fileIsDir };
        }
        return {
            name: String(folderModel.get(index, "fileName")),
            path: String(folderModel.get(index, "filePath")),
            url: String(folderModel.get(index, "fileUrl")),
            isDir: folderModel.get(index, "fileIsDir") === true
        };
    }

    /** Where a url stands in the list on screen now, or -1. */
    function rowOf(url: string): int {
        if (url.length === 0)
            return -1;
        const count = root.searching ? searchResults.count : folderModel.count;
        for (let i = 0; i < count; i++)
            if (root.entryAt(i).url === url)
                return i;
        return -1;
    }

    function setSelection(entries) {
        const dirs = {};
        for (const entry of entries)
            if (entry.isDir)
                dirs[entry.url] = true;
        root.selectedDirs = dirs;
        root.selectedUrls = entries.map(entry => entry.url);
    }

    function clearSelection() {
        root.setSelection([]);
        root.anchorUrl = "";
        root.cursorUrl = "";
    }

    /**
     * A click or an arrow key on a row. With several allowed, Ctrl adds or takes
     * away one row and Shift takes in everything from the anchor. Otherwise the
     * row becomes the whole selection.
     */
    function selectIndex(index: int, modifiers: int) {
        const entry = root.entryAt(index);
        if (!entry)
            return;
        const anchor = root.rowOf(root.anchorUrl);
        const extend = root.multiple && (modifiers & Qt.ShiftModifier) && anchor >= 0;
        const toggle = root.multiple && (modifiers & Qt.ControlModifier);
        if (extend) {
            const entries = [];
            for (let i = Math.min(anchor, index); i <= Math.max(anchor, index); i++)
                entries.push(root.entryAt(i));
            root.setSelection(entries);
        } else if (toggle) {
            const kept = [];
            let had = false;
            for (const url of root.selectedUrls) {
                if (url === entry.url)
                    had = true;
                else
                    kept.push({ url: url, isDir: root.selectedDirs[url] === true });
            }
            if (!had)
                kept.push(entry);
            root.setSelection(kept);
            root.anchorUrl = entry.url;
        } else {
            root.setSelection([entry]);
            root.anchorUrl = entry.url;
        }
        root.cursorUrl = entry.url;
        fileList.positionViewAtIndex(index, ListView.Contain);
        // Picking a file while saving borrows its name, the usual way to
        // overwrite one on purpose. A search hit lives in a folder of its own.
        if (root.saving && !entry.isDir)
            root.borrowName(entry);
    }

    function borrowName(entry) {
        const slash = entry.path.lastIndexOf("/");
        const folder = entry.path.slice(0, slash) || "/";
        root.saveDir = folder === root.currentPath ? "" : folder;
        root.setSaveName(entry.path.slice(slash + 1));
    }

    function moveCursor(step: int, modifiers: int) {
        const count = fileList.count;
        if (count === 0)
            return;
        const cursor = root.rowOf(root.cursorUrl);
        const next = cursor < 0 ? (step > 0 ? 0 : count - 1)
            : Math.max(0, Math.min(count - 1, cursor + step));
        root.selectIndex(next, modifiers & Qt.ShiftModifier);
    }

    /** A double click on a row: into a folder, or take the file. */
    function activateIndex(index: int) {
        const entry = root.entryAt(index);
        if (entry)
            root.activateEntry(entry);
    }

    /** Into a folder, or take the file. */
    function activateEntry(entry) {
        if (entry.isDir) {
            root.enterFolder(entry.path);
        } else if (root.saving) {
            root.borrowName(entry);
            root.accept();
        } else if (!root.directory) {
            root.setSelection([entry]);
            root.accept();
        }
    }

    function leaveFolder() {
        root.saveDir = "";
        if (!root.searching)
            root.scrollMemory[String(folderModel.folder)] = fileList.contentY;
        root.clearSelection();
        root.searchOpen = false;
        root.pathOpen = false;
        searchField.text = "";
        root.restoreScrollPending = true;
    }

    function enterFolder(path: string) {
        // By path: the folder model spells its url with spaces and letters
        // outside ASCII as they are, and the url made here escapes them, so
        // the folder on screen did not count as itself.
        if ((path.replace(/(.)\/+$/, "$1")) === root.currentPath)
            return;
        root.leaveFolder();
        folderModel.folder = root.urlOf(path);
    }

    function goBack() {
        if (folderModel.currentFolderHistoryIndex <= 0)
            return;
        root.leaveFolder();
        folderModel.navigateBack();
    }

    function goForward() {
        if (folderModel.currentFolderHistoryIndex >= folderModel.folderHistory.length - 1)
            return;
        root.leaveFolder();
        folderModel.navigateForward();
    }

    function goUp() {
        if (root.currentPath === "/")
            return;
        root.enterFolder(root.currentPath.slice(0, root.currentPath.lastIndexOf("/")) || "/");
    }

    function openSearch(text: string) {
        root.pathOpen = false;
        root.searchOpen = true;
        searchField.text = text;
        searchField.input.forceActiveFocus();
    }

    function closeSearch() {
        root.searchOpen = false;
        searchField.text = "";
        root.clearSelection();
        fileList.forceActiveFocus();
    }

    function openPathEntry() {
        root.searchOpen = false;
        searchField.text = "";
        root.pathOpen = true;
        pathField.failed = false;
        pathField.text = root.currentPath === "/" ? "/" : `${root.currentPath}/`;
        pathField.input.forceActiveFocus();
        pathField.input.cursorPosition = pathField.text.length;
    }

    function closePathEntry() {
        root.pathOpen = false;
        fileList.forceActiveFocus();
    }

    /** A path typed in: a folder is gone into, a file is taken the way picking it would. */
    function goToTyped(text: string) {
        let path = text.trim();
        if (path === "~" || path.startsWith("~/"))
            path = root.homePath + path.slice(1);
        else if (!path.startsWith("/"))
            path = root.childPath(path);
        path = path.replace(/(.)\/+$/, "$1");
        probe.check(path, kind => {
            if (kind === "d") {
                root.closePathEntry();
                root.enterFolder(path);
            } else if (kind === "f" && !root.directory) {
                const slash = path.lastIndexOf("/");
                root.enterFolder(path.slice(0, slash) || "/");
                if (root.saving) {
                    root.setSaveName(path.slice(slash + 1));
                    root.accept();
                } else {
                    root.answer([root.urlOf(path)]);
                }
            } else {
                pathField.failed = true;
            }
        });
    }

    /**
     * The folder a save goes to when a search hit below the one on screen was
     * picked, empty otherwise. The hit's name alone is the file name. Its
     * folder is kept here rather than in the name, which may not hold a "/".
     */
    property string saveDir: ""

    function setSaveName(name: string) {
        nameField.text = name;
        // The name without its extension, ready to be typed over.
        const dot = name.lastIndexOf(".");
        nameField.input.select(0, dot > 0 ? dot : name.length);
    }

    readonly property string saveName: nameField.text.trim()
    readonly property bool saveNameUsable: root.saveName.length > 0 && root.saveName !== "." && root.saveName !== ".." && !root.saveName.includes("/")

    readonly property bool canAccept: root.saving ? root.saveNameUsable
        : root.directory ? true
        : root.selectedUrls.length > 0

    function accept() {
        if (!root.canAccept)
            return;
        if (root.saving) {
            const path = root.saveDir.length > 0 ? `${root.saveDir === "/" ? "" : root.saveDir}/${root.saveName}` : root.childPath(root.saveName);
            // A folder by that name is gone into, as the file manager does. A
            // file by that name is asked about before it is written over.
            probe.check(path, kind => {
                if (kind === "d") {
                    nameField.text = "";
                    root.enterFolder(path);
                } else if (kind === "f") {
                    replaceDialog.ask([root.saveName], [root.urlOf(path)]);
                } else {
                    root.answer([root.urlOf(path)]);
                }
            });
            return;
        }
        if (root.directory) {
            const folder = root.selectedUrls.length === 1 && root.selectedDirs[root.selectedUrls[0]] ? root.selectedUrls[0] : root.urlOf(root.currentPath);
            // Saving several files into a folder asks first about the ones
            // already there, as saving one does.
            const names = root.mode === "savefiles" ? (root.request.files ?? []) : [];
            if (names.length === 0) {
                root.answer([folder]);
                return;
            }
            existing.check(root.pathOf(folder), names, taken => {
                if (taken.length > 0)
                    replaceDialog.ask(taken, [folder]);
                else
                    root.answer([folder]);
            });
            return;
        }
        const files = root.selectedUrls.filter(url => !root.selectedDirs[url]);
        if (files.length > 0) {
            root.answer(root.multiple ? files : [files[0]]);
        } else if (root.selectedUrls.length === 1) {
            // Only a folder is picked, and a folder is no answer to "open a file".
            root.enterFolder(root.pathOf(root.selectedUrls[0]));
        }
    }

    Keys.onPressed: event => {
        const alt = event.modifiers & Qt.AltModifier;
        const ctrl = event.modifiers & Qt.ControlModifier;
        // The question about replacing a file takes nothing but its own answer.
        if (replaceDialog.visible) {
            if (event.key === Qt.Key_Escape)
                replaceDialog.visible = false;
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape) {
            if (root.pathOpen)
                root.closePathEntry();
            else if (root.searchOpen)
                root.closeSearch();
            else
                FilePicker.cancel();
        } else if (alt && event.key === Qt.Key_Left) {
            root.goBack();
        } else if (alt && event.key === Qt.Key_Right) {
            root.goForward();
        } else if (alt && event.key === Qt.Key_Up) {
            root.goUp();
        } else if (event.key === Qt.Key_Backspace && !root.searchOpen && !root.pathOpen) {
            root.goUp();
        } else if (ctrl && event.key === Qt.Key_L) {
            root.openPathEntry();
        } else if (ctrl && event.key === Qt.Key_F) {
            if (root.searchOpen)
                root.closeSearch();
            else
                root.openSearch("");
        } else if (ctrl && event.key === Qt.Key_H) {
            root.showHidden = !root.showHidden;
        } else if (event.key === Qt.Key_Menu || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_F10)) {
            // The menu a right click opens, at the row the keys are on.
            const cursor = root.rowOf(root.cursorUrl);
            const row = cursor >= 0 ? fileList.itemAtIndex(cursor) : null;
            const point = row ? row.mapToItem(root, ExLooks.spacing.xl, row.height) : fileList.mapToItem(root, ExLooks.spacing.xl, 0);
            viewMenu.target = row && root.selectedUrls.length > 0 ? root.entryAt(cursor).path : "";
            viewMenu.openAt(point.x, point.y);
        } else if (!ctrl && !alt && event.text.length === 1 && event.text.charCodeAt(0) > 0x20) {
            // Typing at the list searches.
            root.openSearch(event.text);
        } else {
            return;
        }
        event.accepted = true;
    }

    Component.onCompleted: {
        if (root.saving) {
            root.setSaveName(root.request.saveName ?? "");
            nameField.input.forceActiveFocus();
        } else {
            fileList.forceActiveFocus();
        }
    }

    FolderListModelWithHistory {
        id: folderModel

        // Where the application asked to start, or where the last pick left off.
        // Bound only until the first move, which assigns over it.
        folder: {
            const asked = root.request.currentFolder ?? "";
            if (asked.length > 0)
                return root.urlOf(asked);
            if (FilePicker.lastFolder.length > 0)
                return FilePicker.lastFolder;
            return Directories.home;
        }
        showDirs: true
        showDirsFirst: root.foldersFirst
        showDotAndDotDot: false
        showHidden: root.showHidden
        showFiles: !root.directory
        caseSensitive: false
        sortCaseSensitive: false
        sortReversed: root.sortDescending
        sortField: root.sortColumn === 1 ? FolderListModel.Size : root.sortColumn === 2 ? FolderListModel.Time : FolderListModel.Name
        nameFilters: root.namePatterns

        onStatusChanged: {
            if (folderModel.status === FolderListModel.Ready) {
                FilePicker.lastFolder = String(folderModel.folder);
                if (root.restoreScrollPending) {
                    root.restoreScrollPending = false;
                    const y = root.scrollMemory[String(folderModel.folder)] ?? 0;
                    Qt.callLater(() => fileList.contentY = Math.min(y, Math.max(0, fileList.contentHeight - fileList.height)));
                }
            }
        }
    }

    // What the search found, in the folder on screen and every folder below it.
    ListModel {
        id: searchResults
    }

    Timer {
        id: searchDelay
        interval: 180
        onTriggered: search.start()
    }

    Connections {
        target: searchField
        function onTextChanged() {
            searchResults.clear();
            if (searchField.text.length > 0)
                searchDelay.restart();
            else
                searchDelay.stop();
        }
    }

    Process {
        id: search

        property string folder: ""
        property string pattern: ""
        // Each run is numbered and says its number first, so the output of
        // one stopped for a newer search is told apart and dropped.
        property int serial: 0

        function start() {
            search.running = false;
            search.serial++;
            // Wildcards typed in are looked for as they are.
            search.pattern = `*${searchField.text.replace(/[*?[\]\\]/g, "\\$&")}*`;
            search.folder = root.currentPath;
            search.running = true;
        }

        // Bounded in time and in count, so a search over a very large tree
        // cannot keep going. Hidden folders are not gone into unless hidden
        // files are shown. The arguments are handed over as arguments, not
        // spliced into the script, so nothing typed is run. The script takes
        // the walk with it when it is stopped for a newer search.
        command: ["sh", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/files/search.sh")),
            search.folder, search.pattern, root.showHidden ? "1" : "0", String(search.serial)]

        stdout: StdioCollector {
            id: searchOutput

            onStreamFinished: {
                const text = searchOutput.text;
                const newline = text.indexOf("\n");
                if (newline < 0 || text.slice(0, newline) !== String(search.serial))
                    return;
                const records = text.slice(newline + 1).split("\0");
                searchResults.clear();
                if (!root.searching)
                    return;
                const base = search.folder === "/" ? "" : search.folder;
                const found = [];
                for (const record of records) {
                    const parts = record.split("\t");
                    if (parts.length < 4)
                        continue;
                    const path = parts.slice(3).join("\t");
                    const isDir = parts[0] === "d";
                    const name = path.slice(path.lastIndexOf("/") + 1);
                    if (root.directory && !isDir)
                        continue;
                    if (!isDir && !root.matchesFilter(name))
                        continue;
                    const seconds = parseFloat(parts[2]) || 0;
                    found.push({
                        fileName: path.startsWith(`${base}/`) ? path.slice(base.length + 1) : path,
                        filePath: path,
                        fileUrl: root.urlOf(path),
                        fileIsDir: isDir,
                        fileSize: parseInt(parts[1], 10) || 0,
                        fileModified: new Date(seconds * 1000)
                    });
                }
                // What is found close by comes before what is found deep down,
                // which find alone does not keep to.
                const depth = entry => entry.fileName.split("/").length;
                found.sort((a, b) => depth(a) - depth(b)
                    || (root.foldersFirst ? Number(b.fileIsDir) - Number(a.fileIsDir) : 0)
                    || a.fileName.localeCompare(b.fileName));
                for (const entry of found)
                    searchResults.append(entry);
            }
        }
    }

    // Asks whether a path is a folder, a file, or nothing, then answers the
    // callback. One question at a time: a newer one replaces the one before,
    // and the answer of one replaced is dropped by its number.
    Process {
        id: probe

        property string path: ""
        property var callback: null
        property int serial: 0

        function check(path: string, callback) {
            probe.running = false;
            probe.serial++;
            probe.path = path;
            probe.callback = callback;
            probe.running = true;
        }

        command: ["sh", "-c", "echo \"$2\"; if [ -d \"$1\" ]; then echo d; elif [ -e \"$1\" ]; then echo f; else echo n; fi", "yuki-file-probe", probe.path, String(probe.serial)]

        stdout: StdioCollector {
            id: probeOutput

            onStreamFinished: {
                const [serial, kind] = probeOutput.text.trim().split("\n");
                if (serial !== String(probe.serial))
                    return;
                const callback = probe.callback;
                probe.callback = null;
                if (callback)
                    callback((kind ?? "").trim());
            }
        }
    }

    // Which of the names asked about are already in a folder. Numbered like
    // the probe, so the answer of a check replaced by a newer one is dropped
    // rather than taken for the newer one's.
    Process {
        id: existing

        property var callback: null
        property int serial: 0

        function check(folder: string, names, callback) {
            existing.running = false;
            existing.serial++;
            existing.callback = callback;
            existing.command = ["sh", "-c", "s=\"$1\"; d=\"$2\"; shift 2; printf '%s\\n' \"$s\"; for f; do [ -e \"$d/$f\" ] && printf '%s\\n' \"$f\"; done; true", "yuki-file-existing", String(existing.serial), folder, ...names];
            existing.running = true;
        }

        stdout: StdioCollector {
            id: existingOutput

            onStreamFinished: {
                const lines = existingOutput.text.split("\n");
                if (lines[0] !== String(existing.serial))
                    return;
                const callback = existing.callback;
                existing.callback = null;
                if (callback)
                    callback(lines.slice(1).filter(line => line.length > 0));
            }
        }
    }

    // The folders the file manager has bookmarked, as it keeps them: one url
    // per line, then an optional name.
    FileView {
        id: bookmarksFile

        path: `${root.homePath}/.config/gtk-3.0/bookmarks`
        watchChanges: true
        onFileChanged: bookmarksFile.reload()
        onLoadFailed: root.bookmarks = []
        onLoaded: {
            const found = [];
            for (const line of bookmarksFile.text().split("\n")) {
                const trimmed = line.trim();
                if (!trimmed.startsWith("file://"))
                    continue;
                const space = trimmed.indexOf(" ");
                const url = space >= 0 ? trimmed.slice(0, space) : trimmed;
                const path = root.pathOf(url);
                const name = space >= 0 ? trimmed.slice(space + 1).trim() : "";
                found.push({ name: name.length > 0 ? name : (path.slice(path.lastIndexOf("/") + 1) || path), path: path });
            }
            root.bookmarks = found;
        }
    }

    readonly property var places: {
        const standard = [
            { glyph: "home", name: Translation.tr("Home"), path: root.homePath },
            { glyph: "description", name: Translation.tr("Documents"), path: root.pathOf(Directories.documents) },
            { glyph: "download", name: Translation.tr("Downloads"), path: root.pathOf(Directories.downloads) },
            { glyph: "image", name: Translation.tr("Pictures"), path: root.pathOf(Directories.pictures) },
            { glyph: "movie", name: Translation.tr("Videos"), path: root.pathOf(Directories.videos) },
            { glyph: "music_note", name: Translation.tr("Music"), path: root.pathOf(Directories.music) }
        ];
        // A folder the user never had is not a place to go.
        const seen = new Set();
        const shown = standard.filter(place => {
            if (seen.has(place.path) || (place.path === root.homePath && place.glyph !== "home"))
                return false;
            seen.add(place.path);
            return true;
        });
        shown.push({ glyph: "hard_drive", name: Translation.tr("Computer"), path: "/" });
        if (root.bookmarks.length > 0) {
            shown.push({ header: Translation.tr("Bookmarks") });
            for (const bookmark of root.bookmarks)
                shown.push({ glyph: "bookmark", name: bookmark.name, path: bookmark.path });
        }
        return shown;
    }

    /** The parts of the path on screen, the home folder standing as one. */
    readonly property var crumbs: {
        const path = root.currentPath;
        const underHome = path === root.homePath || path.startsWith(`${root.homePath}/`);
        const crumbs = [underHome ? { glyph: "home", label: Translation.tr("Home"), path: root.homePath } : { glyph: "hard_drive", label: "", path: "/" }];
        let walked = underHome ? root.homePath : "";
        const rest = underHome ? path.slice(root.homePath.length) : path;
        for (const part of rest.split("/")) {
            if (part.length === 0)
                continue;
            walked += `/${part}`;
            crumbs.push({ glyph: "", label: part, path: walked });
        }
        return crumbs;
    }

    component ToolButton: AbstractButton {
        id: tool

        ExPrimaryOnly {
            z: 1
        }

        property string glyph
        property bool toggled: false

        implicitWidth: 34
        implicitHeight: 34
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        opacity: enabled ? 1 : ExLooks.colors.disabledOpacity

        background: Rectangle {
            radius: ExLooks.radius.control
            color: tool.toggled ? ExLooks.colors.tonal : "transparent"

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: tool.hovered && tool.enabled
                pressed: tool.down
            }
        }
        contentItem: Item {
            ExGlyph {
                anchors.centerIn: parent
                text: tool.glyph
                size: 20
                color: tool.toggled ? ExLooks.colors.tonalInk : ExLooks.colors.text
            }
        }
    }

    component HeaderCell: AbstractButton {
        id: cell

        ExPrimaryOnly {
            z: 1
        }

        property int column: 0
        property bool alignRight: false
        readonly property bool active: root.sortColumn === cell.column

        implicitHeight: 30
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: {
            if (cell.active) {
                root.sortDescending = !root.sortDescending;
            } else {
                root.sortColumn = cell.column;
                root.sortDescending = false;
            }
        }

        contentItem: RowLayout {
            spacing: 2
            layoutDirection: cell.alignRight ? Qt.RightToLeft : Qt.LeftToRight

            ExText {
                text: cell.text
                role: "caption"
                dim: !cell.active && !cell.hovered
                font.weight: ExLooks.font.weightLabel
            }
            ExGlyph {
                visible: cell.active
                text: root.sortDescending ? "arrow_downward" : "arrow_upward"
                size: 14
                color: ExLooks.colors.textDim
            }
            Item {
                Layout.fillWidth: true
            }
        }
    }

    component FileIcon: Item {
        id: icon

        property string name
        property bool isDir
        property int attempt: 0

        implicitWidth: 24
        implicitHeight: 24

        Image {
            id: picture
            anchors.fill: parent
            sourceSize: Qt.size(48, 48)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            source: icon.attempt < root.iconThemeRoots.length ? `file://${root.iconThemeRoots[icon.attempt]}/${root.iconRelative(icon.name, icon.isDir)}` : ""
            onStatusChanged: {
                if (status === Image.Error)
                    icon.attempt++;
            }
        }
        ExGlyph {
            anchors.centerIn: parent
            visible: picture.status !== Image.Ready
            text: root.glyphFor(icon.name, icon.isDir)
            size: 22
            fill: 1
            color: icon.isDir ? ExLooks.colors.accent : ExLooks.colors.textDim
        }
    }

    /** A menu opened over the window, placed at a point in it. */
    component PickerMenu: Popup {
        id: menu

        default property alias items: plane.items

        /** When the menu last closed, to tell a second click on its button from a first. */
        property real closedAt: 0

        function openAt(x: real, y: real) {
            menu.x = Math.max(ExLooks.spacing.s, Math.min(x, root.width - plane.implicitWidth - ExLooks.spacing.s));
            menu.y = Math.max(ExLooks.spacing.s, Math.min(y, root.height - plane.implicitHeight - ExLooks.spacing.s));
            menu.open();
        }

        // For a button that opens the menu. Pressing it again is a press outside
        // the menu, which has already closed it by the time the click arrives,
        // and the click must not open it again.
        function toggleAt(x: real, y: real) {
            if (menu.visible || Date.now() - menu.closedAt < 300) {
                menu.close();
                return;
            }
            menu.openAt(x, y);
        }

        onClosed: menu.closedAt = Date.now()

        parent: root
        padding: 0
        // Takes the keys while open, so Escape closes the menu and not the picker.
        focus: true
        background: null
        contentItem: ExMenu {
            id: plane
            implicitWidth: 300
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ExLooks.colors.surface
    }

    // The mouse's back and forward buttons.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onPressed: event => {
            if (event.button === Qt.BackButton)
                root.goBack();
            else
                root.goForward();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The title, then the way to the folder on screen.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: ExLooks.spacing.m
            Layout.bottomMargin: ExLooks.spacing.s
            spacing: ExLooks.spacing.s

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: ExLooks.spacing.xs
                spacing: ExLooks.spacing.xs

                ExText {
                    Layout.fillWidth: true
                    text: root.titleText
                    role: "title"
                }
                ToolButton {
                    glyph: "search"
                    toggled: root.searchOpen
                    onClicked: {
                        if (root.searchOpen)
                            root.closeSearch();
                        else
                            root.openSearch("");
                    }
                }
                ToolButton {
                    id: moreButton
                    glyph: "more_vert"
                    onClicked: {
                        const corner = moreButton.mapToItem(root, moreButton.width, moreButton.height + ExLooks.spacing.xs);
                        viewMenu.target = "";
                        viewMenu.toggleAt(corner.x - ExLooks.sizes.menuWidth, corner.y);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ExLooks.spacing.xs

                ToolButton {
                    glyph: "arrow_back"
                    enabled: folderModel.currentFolderHistoryIndex > 0
                    onClicked: root.goBack()
                }
                ToolButton {
                    glyph: "arrow_forward"
                    enabled: folderModel.currentFolderHistoryIndex < folderModel.folderHistory.length - 1
                    onClicked: root.goForward()
                }
                ToolButton {
                    glyph: "arrow_upward"
                    enabled: root.currentPath !== "/"
                    onClicked: root.goUp()
                }

                Item {
                    Layout.fillWidth: true
                    Layout.leftMargin: ExLooks.spacing.xs
                    implicitHeight: 36

                    // The path as buttons, one per folder on the way. A click on
                    // the empty stretch after them turns it into a field to type
                    // a path into.
                    Rectangle {
                        anchors.fill: parent
                        visible: !root.searchOpen && !root.pathOpen
                        radius: ExLooks.radius.control
                        color: ExLooks.colors.surfaceSunken

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.openPathEntry()
                        }

                        Flickable {
                            id: crumbScroller

                            anchors.fill: parent
                            anchors.margins: 2
                            clip: true
                            contentWidth: crumbRow.implicitWidth
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            // The deep end of a long path is the part that matters.
                            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                            onWidthChanged: contentX = Math.max(0, contentWidth - width)

                            Row {
                                id: crumbRow
                                height: parent.height

                                Repeater {
                                    model: root.crumbs

                                    Row {
                                        id: crumb

                                        required property var modelData
                                        required property int index
                                        readonly property bool last: crumb.index === root.crumbs.length - 1

                                        height: crumbRow.height

                                        ExGlyph {
                                            visible: crumb.index > 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "chevron_right"
                                            size: 16
                                            color: ExLooks.colors.textDim
                                        }
                                        AbstractButton {
                                            id: crumbButton

                                            ExPrimaryOnly {
                                                z: 1
                                            }

                                            height: parent.height
                                            implicitWidth: crumbContent.implicitWidth + 2 * ExLooks.spacing.s
                                            hoverEnabled: true
                                            focusPolicy: Qt.NoFocus
                                            onClicked: root.enterFolder(crumb.modelData.path)

                                            background: Rectangle {
                                                radius: ExLooks.radius.menuItem
                                                color: crumb.last ? ExLooks.colors.surface : "transparent"

                                                ExStateLayer {
                                                    ink: ExLooks.colors.text
                                                    hovered: crumbButton.hovered
                                                    pressed: crumbButton.down
                                                }
                                            }
                                            contentItem: Item {
                                                Row {
                                                    id: crumbContent
                                                    anchors.centerIn: parent
                                                    spacing: ExLooks.spacing.xs

                                                    ExGlyph {
                                                        visible: crumb.modelData.glyph.length > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: crumb.modelData.glyph
                                                        size: 18
                                                        color: crumb.last ? ExLooks.colors.text : ExLooks.colors.textDim
                                                    }
                                                    ExText {
                                                        visible: crumb.modelData.label.length > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: crumb.modelData.label
                                                        role: "label"
                                                        dim: !crumb.last
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // The start of a path that does not fit fades out
                        // rather than being cut off mid letter.
                        Rectangle {
                            visible: crumbScroller.contentX > 0
                            width: 32
                            height: parent.height
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0.3
                                    color: ExLooks.colors.surfaceSunken
                                }
                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }
                            }
                        }
                    }

                    ExTextField {
                        id: pathField

                        property bool failed: false

                        anchors.fill: parent
                        visible: root.pathOpen
                        glyph: "folder_open"
                        border.color: pathField.failed ? ExLooks.colors.destructive : (pathField.input.activeFocus ? ExLooks.colors.accent : ExLooks.colors.border)

                        Connections {
                            target: pathField.input

                            function onTextEdited() {
                                pathField.failed = false;
                            }
                            function onAccepted() {
                                root.goToTyped(pathField.text);
                            }
                            // Clicking away puts the path buttons back.
                            function onActiveFocusChanged() {
                                if (!pathField.input.activeFocus && root.pathOpen)
                                    root.pathOpen = false;
                            }
                        }
                    }

                    ExTextField {
                        id: searchField

                        anchors.fill: parent
                        visible: root.searchOpen
                        glyph: "search"
                        placeholder: Translation.tr("Search in this folder and below")
                        Keys.onDownPressed: {
                            fileList.forceActiveFocus();
                            root.moveCursor(1, 0);
                        }

                        Connections {
                            target: searchField.input

                            function onAccepted() {
                                fileList.forceActiveFocus();
                                if (fileList.count > 0)
                                    root.selectIndex(0, 0);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: ExLooks.colors.border
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Places.
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 196
                color: ExLooks.colors.surfaceSunken

                ListView {
                    anchors.fill: parent
                    anchors.margins: ExLooks.spacing.s
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.places

                    delegate: Item {
                        id: place

                        required property var modelData
                        readonly property bool isHeader: place.modelData.header !== undefined
                        readonly property bool here: !place.isHeader && place.modelData.path === root.currentPath && !root.searching

                        width: ListView.view.width
                        height: place.isHeader ? 34 : 36

                        ExText {
                            visible: place.isHeader
                            anchors.left: parent.left
                            anchors.leftMargin: ExLooks.spacing.m
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: ExLooks.spacing.xs
                            text: place.modelData.header ?? ""
                            role: "caption"
                            dim: true
                            font.weight: ExLooks.font.weightLabel
                        }

                        AbstractButton {
                            id: placeButton

                            ExPrimaryOnly {
                                z: 1
                            }

                            visible: !place.isHeader
                            anchors.fill: parent
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            onClicked: root.enterFolder(place.modelData.path)

                            background: Rectangle {
                                radius: ExLooks.radius.menuItem
                                color: place.here ? ExLooks.colors.tonal : "transparent"

                                ExStateLayer {
                                    ink: place.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                    hovered: placeButton.hovered
                                    pressed: placeButton.down
                                }
                            }
                            contentItem: RowLayout {
                                spacing: ExLooks.spacing.m

                                ExGlyph {
                                    Layout.leftMargin: ExLooks.spacing.m
                                    text: place.modelData.glyph ?? ""
                                    size: 20
                                    fill: place.here ? 1 : 0
                                    color: place.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                }
                                ExText {
                                    Layout.fillWidth: true
                                    Layout.rightMargin: ExLooks.spacing.s
                                    text: place.modelData.name ?? ""
                                    color: place.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: ExLooks.colors.border
            }

            // The folder.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: ExLooks.spacing.s + ExLooks.spacing.m + 24 + ExLooks.spacing.m
                    Layout.rightMargin: ExLooks.spacing.s + ExLooks.spacing.m
                    Layout.topMargin: ExLooks.spacing.xs
                    spacing: ExLooks.spacing.m

                    HeaderCell {
                        Layout.fillWidth: true
                        text: Translation.tr("Name")
                        column: 0
                    }
                    HeaderCell {
                        visible: !root.directory
                        Layout.preferredWidth: root.sizeColumnWidth
                        text: Translation.tr("Size")
                        column: 1
                        alignRight: true
                    }
                    HeaderCell {
                        Layout.preferredWidth: root.dateColumnWidth
                        text: Translation.tr("Modified")
                        column: 2
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: fileList

                        anchors.fill: parent
                        anchors.margins: ExLooks.spacing.s
                        anchors.topMargin: 0
                        clip: true
                        focus: true
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false
                        model: root.searching ? searchResults : folderModel

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Keys.onUpPressed: event => root.moveCursor(-1, event.modifiers)
                        Keys.onDownPressed: event => root.moveCursor(1, event.modifiers)
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Home) {
                                root.selectIndex(0, event.modifiers & Qt.ShiftModifier);
                            } else if (event.key === Qt.Key_End) {
                                root.selectIndex(fileList.count - 1, event.modifiers & Qt.ShiftModifier);
                            } else if (event.key === Qt.Key_PageDown) {
                                root.moveCursor(Math.max(1, Math.floor(fileList.height / root.rowHeight) - 1), event.modifiers);
                            } else if (event.key === Qt.Key_PageUp) {
                                root.moveCursor(-Math.max(1, Math.floor(fileList.height / root.rowHeight) - 1), event.modifiers);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // The one thing selected, taken by its url.
                                if (root.selectedUrls.length === 1) {
                                    const url = root.selectedUrls[0];
                                    root.activateEntry({ path: root.pathOf(url), url: url, isDir: root.selectedDirs[url] === true });
                                } else {
                                    root.accept();
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_A && root.multiple) {
                                const entries = [];
                                for (let i = 0; i < fileList.count; i++)
                                    entries.push(root.entryAt(i));
                                root.setSelection(entries);
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }

                        // A click on the empty space below the rows lets go of the selection.
                        MouseArea {
                            z: -1
                            width: fileList.width
                            height: Math.max(fileList.height, fileList.contentHeight)
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: event => {
                                fileList.forceActiveFocus();
                                root.clearSelection();
                                if (event.button === Qt.RightButton) {
                                    const point = mapToItem(root, event.x, event.y);
                                    viewMenu.target = "";
                                    viewMenu.openAt(point.x, point.y);
                                }
                            }
                        }

                        delegate: Item {
                            id: row

                            required property int index
                            required property string fileName
                            required property string filePath
                            required property var fileUrl
                            required property bool fileIsDir
                            required property var fileSize
                            required property var fileModified
                            readonly property bool selected: root.selectedUrls.includes(String(row.fileUrl))

                            width: ListView.view.width
                            height: root.rowHeight

                            Rectangle {
                                anchors.fill: parent
                                radius: ExLooks.radius.menuItem
                                color: row.selected ? ExLooks.colors.tonal : "transparent"
                                // The row the keys move from, when the selection does not show it.
                                border.width: fileList.activeFocus && root.cursorUrl === String(row.fileUrl) && !row.selected ? 1 : 0
                                border.color: ExLooks.colors.accent

                                ExStateLayer {
                                    ink: row.selected ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                    hovered: rowMouse.containsMouse
                                    pressed: rowMouse.pressed
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: ExLooks.spacing.m
                                anchors.rightMargin: ExLooks.spacing.m
                                spacing: ExLooks.spacing.m

                                FileIcon {
                                    name: row.fileName
                                    isDir: row.fileIsDir
                                }
                                ExText {
                                    Layout.fillWidth: true
                                    text: row.fileName
                                    elide: Text.ElideMiddle
                                    color: row.selected ? ExLooks.colors.tonalInk : ExLooks.colors.text
                                }
                                ExText {
                                    visible: !root.directory
                                    Layout.preferredWidth: root.sizeColumnWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: row.fileIsDir ? "" : root.humanSize(row.fileSize)
                                    role: "caption"
                                    dim: true
                                }
                                ExText {
                                    Layout.preferredWidth: root.dateColumnWidth
                                    text: root.shortDate(row.fileModified)
                                    role: "caption"
                                    dim: true
                                }
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: event => {
                                    fileList.forceActiveFocus();
                                    if (event.button === Qt.RightButton) {
                                        if (!row.selected)
                                            root.selectIndex(row.index, 0);
                                        const point = mapToItem(root, event.x, event.y);
                                        viewMenu.target = row.filePath;
                                        viewMenu.openAt(point.x, point.y);
                                    } else {
                                        root.selectIndex(row.index, event.modifiers);
                                    }
                                }
                                onDoubleClicked: event => {
                                    if (event.button === Qt.LeftButton)
                                        root.activateIndex(row.index);
                                }
                            }
                        }
                    }

                    ExText {
                        anchors.centerIn: parent
                        visible: fileList.count === 0 && (root.searching || folderModel.status === FolderListModel.Ready)
                        text: root.searching ? (search.running || searchDelay.running ? Translation.tr("Searching…") : Translation.tr("Nothing found"))
                            : root.directory ? Translation.tr("No folders here")
                            : Translation.tr("This folder is empty")
                        dim: true
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: ExLooks.colors.border
        }

        // What to answer with.
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: ExLooks.spacing.m
            spacing: ExLooks.spacing.s

            ExTextField {
                id: nameField

                visible: root.saving
                Layout.fillWidth: true
                Layout.preferredHeight: ExLooks.sizes.control
                glyph: "edit"
                placeholder: Translation.tr("File name")
                Keys.onDownPressed: {
                    fileList.forceActiveFocus();
                    root.moveCursor(1, 0);
                }

                Connections {
                    target: nameField.input

                    function onAccepted() {
                        root.accept();
                    }
                    // A name typed in goes to the folder on screen.
                    function onTextEdited() {
                        root.saveDir = "";
                    }
                }
            }

            ExText {
                visible: !root.saving
                Layout.fillWidth: true
                Layout.leftMargin: ExLooks.spacing.xs
                dim: true
                text: root.selectedUrls.length > 1 ? Translation.tr("%1 selected").arg(root.selectedUrls.length)
                    : root.selectedUrls.length === 1 ? root.pathOf(root.selectedUrls[0]).split("/").pop()
                    : root.directory ? (root.currentPath.split("/").pop() || "/")
                    : ""
            }

            ExButton {
                id: filterButton

                visible: root.filters.length > 1
                Layout.maximumWidth: 260
                kind: "control"
                glyph: "filter_list"
                text: root.filters[root.filterIndex]?.name ?? ""
                focusPolicy: Qt.NoFocus
                onClicked: {
                    const corner = filterButton.mapToItem(root, 0, 0);
                    filterMenu.toggleAt(corner.x, corner.y - filterMenu.contentItem.implicitHeight - ExLooks.spacing.xs);
                }
            }

            ExButton {
                kind: "control"
                text: Translation.tr("Cancel")
                focusPolicy: Qt.NoFocus
                onClicked: FilePicker.cancel()
            }
            ExButton {
                kind: "accent"
                text: root.acceptText
                enabled: root.canAccept
                focusPolicy: Qt.NoFocus
                onClicked: root.accept()
            }
        }
    }

    PickerMenu {
        id: filterMenu

        Repeater {
            model: root.filters

            ExMenuItem {
                required property var modelData
                required property int index

                text: modelData.name
                glyph: index === root.filterIndex ? "check" : ""
                onClicked: {
                    root.filterIndex = index;
                    root.clearSelection();
                    filterMenu.close();
                }
            }
        }
    }

    PickerMenu {
        id: viewMenu

        /** The file the menu was opened on, or none for the folder itself. */
        property string target: ""

        ExMenuItem {
            text: Translation.tr("Copy location")
            glyph: "content_copy"
            onClicked: {
                Quickshell.clipboardText = viewMenu.target.length > 0 ? viewMenu.target : root.currentPath;
                viewMenu.close();
            }
        }
        ExMenuSeparator {}
        ExMenuItem {
            text: Translation.tr("Show hidden files")
            glyph: root.showHidden ? "check" : ""
            shortcut: "Ctrl+H"
            onClicked: {
                root.showHidden = !root.showHidden;
                viewMenu.close();
            }
        }
        ExMenuItem {
            text: Translation.tr("Folders first")
            glyph: root.foldersFirst ? "check" : ""
            onClicked: {
                root.foldersFirst = !root.foldersFirst;
                viewMenu.close();
            }
        }
    }

    // Saving over a file that is already there is asked about first.
    Item {
        id: replaceDialog

        property var names: []
        property var answerUrls: []
        readonly property string name: replaceDialog.names[0] ?? ""

        function ask(names, answerUrls) {
            replaceDialog.names = names;
            replaceDialog.answerUrls = answerUrls;
            replaceDialog.visible = true;
        }

        anchors.fill: parent
        visible: false
        onVisibleChanged: {
            if (replaceDialog.visible)
                replaceButton.forceActiveFocus();
            else
                nameField.input.forceActiveFocus();
        }

        Rectangle {
            anchors.fill: parent
            color: ExLooks.colors.scrim
        }
        MouseArea {
            anchors.fill: parent
        }

        ExSurface {
            anchors.centerIn: parent
            width: 420
            height: dialogColumn.implicitHeight + 2 * ExLooks.spacing.xl
            radius: ExLooks.radius.panel
            elevation: 2

            ColumnLayout {
                id: dialogColumn

                anchors.fill: parent
                anchors.margins: ExLooks.spacing.xl
                spacing: ExLooks.spacing.m

                ExText {
                    Layout.fillWidth: true
                    text: replaceDialog.names.length > 1 ? Translation.tr("Replace %1 files?").arg(replaceDialog.names.length)
                        : Translation.tr("Replace “%1”?").arg(replaceDialog.name)
                    role: "title"
                }
                ExText {
                    Layout.fillWidth: true
                    text: replaceDialog.names.length > 1
                        ? Translation.tr("Files with these names already exist: %1. Replacing them will overwrite their contents.").arg(replaceDialog.names.join(", "))
                        : Translation.tr("A file with this name already exists in “%1”. Replacing it will overwrite its contents.").arg(root.currentPath.split("/").pop() || "/")
                    wrapMode: Text.Wrap
                    dim: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: ExLooks.spacing.s
                    spacing: ExLooks.spacing.s

                    Item {
                        Layout.fillWidth: true
                    }
                    ExButton {
                        kind: "control"
                        text: Translation.tr("Cancel")
                        onClicked: replaceDialog.visible = false
                    }
                    ExButton {
                        id: replaceButton

                        kind: "accent"
                        text: Translation.tr("Replace")
                        Keys.onReturnPressed: replaceButton.clicked()
                        onClicked: root.answer(replaceDialog.answerUrls)
                    }
                }
            }
        }
    }
}
