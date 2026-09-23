pragma ComponentBehavior: Bound
import qs
import qs.core
import qs.core.services
import qs.core.models
import qs.core.functions
import qs.common
import qs.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    focus: true

    readonly property var req: FilePicker.request
    readonly property string mode: root.req.mode ?? "open"
    readonly property bool directory: root.req.directory ?? false
    readonly property var filters: root.req.filters ?? []
    readonly property string titleText: root.mode === "save"
        ? Translation.tr("Save file")
        : (root.directory ? Translation.tr("Select folder") : Translation.tr("Open file"))
    readonly property string headerIcon: root.mode === "save" ? "save_as" : "folder_open"

    property string selectedUrl: ""
    // The full selection. In multi mode Ctrl-click toggles entries; otherwise it holds
    // the single selected url. selectedUrl stays the last-clicked one (drives preview).
    property var selectedUrls: []
    readonly property bool multiple: (root.req.multiple ?? false)
    // Anchor row for Shift-click range selection (index in the active model).
    property int selectionAnchor: -1
    // Exactly one entry selected: the preview shows it. Zero or many -> a summary.
    readonly property bool singleSel: root.selectedUrls.length === 1
    // Row/cell under the cursor, from the single input surface (delegates have no
    // MouseArea of their own now, so hover and clicks are hit-tested centrally).
    property int hoveredIndex: -1
    property int currentFilterIndex: 0

    // Column geometry, shared by the header and every row so they line up.
    readonly property int sizeColumnWidth: 84
    readonly property int dateColumnWidth: 132
    // 0 = name, 1 = size, 2 = modified.
    property int sortColumn: 0
    property bool sortDescending: false

    // View zoom: the icon size drives the row height.
    property int iconSize: 24
    readonly property int rowHeight: root.iconSize + 14
    // The selected row's data, for the preview pane.
    property var selectedInfo: null

    // View options (mirrored to the folder model, toggled from the context menu).
    property bool showHiddenFiles: false
    property bool foldersFirst: true

    // 0 = list (columns), 1 = gallery (grid). Each view keeps its own icon size.
    property int viewMode: 0
    property int gridIconSize: 72

    // Type-ahead search over the current folder (substring, case-insensitive).
    property bool searchActive: false
    property string searchText: ""

    // Per-folder scroll position, so going back lands where you left off instead of
    // snapping to the top. Keyed by folder url; restored only right after a navigation.
    property var scrollMemory: ({})
    property bool pendingScrollRestore: false

    // Nautilus/GTK bookmarks (~/.config/gtk-3.0/bookmarks), shown under the places.
    property var bookmarks: []

    // Places sidebar model: the standard XDG dirs, then the user's Nautilus bookmarks.
    readonly property var placesModel: {
        const base = [
            { icon: "home", name: Translation.tr("Home"), path: Directories.home, header: false },
            { icon: "description", name: Translation.tr("Documents"), path: Directories.documents, header: false },
            { icon: "download", name: Translation.tr("Downloads"), path: Directories.downloads, header: false },
            { icon: "image", name: Translation.tr("Pictures"), path: Directories.pictures, header: false },
            { icon: "movie", name: Translation.tr("Videos"), path: Directories.videos, header: false },
            { icon: "music_note", name: Translation.tr("Music"), path: Directories.music, header: false },
        ];
        if (root.bookmarks.length > 0) {
            base.push({ header: true, name: Translation.tr("Bookmarks"), icon: "", path: "" });
            for (let i = 0; i < root.bookmarks.length; i++)
                base.push({ icon: "bookmark", name: root.bookmarks[i].name, path: root.bookmarks[i].path, header: false });
        }
        return base;
    }

    function humanSize(bytes) {
        if (bytes === undefined || bytes === null || bytes < 0)
            return "";
        if (bytes < 1024)
            return `${bytes} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let n = bytes;
        let i = -1;
        do {
            n /= 1024;
            i++;
        } while (n >= 1024 && i < units.length - 1);
        return `${n < 10 ? n.toFixed(1) : Math.round(n)} ${units[i]}`;
    }

    function shortDate(d) {
        if (!d || typeof d.getTime !== "function" || isNaN(d.getTime()))
            return "";
        return Qt.formatDateTime(d, "d MMM yyyy");
    }

    function fileExt(name) {
        const dot = name.lastIndexOf(".");
        return dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
    }

    // Material Symbol per file category. Crisp and always renders, unlike the
    // breeze theme icons (Qt's SVG renderer silently draws some of them blank).
    function categoryGlyph(name, isDir) {
        if (isDir)
            return "folder";
        const ext = root.fileExt(name);
        if (["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "zst"].includes(ext)) return "folder_zip";
        if (["mp3", "ogg", "wav", "flac", "m4a", "opus", "aac"].includes(ext)) return "music_note";
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "wmv", "flv"].includes(ext)) return "movie";
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic"].includes(ext)) return "image";
        if (ext === "pdf") return "picture_as_pdf";
        if (["appimage", "exe", "bin", "run", "msi", "app"].includes(ext)) return "terminal";
        if (["iso", "img", "dmg"].includes(ext)) return "album";
        if (["sh", "fish", "bash", "py", "js", "ts", "lua", "qml", "c", "cpp", "rs", "go", "java", "kt"].includes(ext)) return "code";
        return "draft";
    }

    // A muted colour per category so type icons read at a glance, without a rainbow.
    function categoryColor(name, isDir) {
        if (isDir)
            return Appearance.colors.colPrimary;
        const ext = root.fileExt(name);
        if (["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "zst", "lz", "lzma"].includes(ext)) return "#d0a45c";
        if (["mp3", "ogg", "wav", "flac", "m4a", "opus", "aac", "mid", "wma"].includes(ext)) return "#b58bd0";
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "ts", "3gp"].includes(ext)) return "#7fa6e0";
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "ico", "tif", "tiff"].includes(ext)) return "#84c07a";
        if (ext === "pdf") return "#d97a7a";
        if (["appimage", "exe", "bin", "run", "msi", "app"].includes(ext)) return "#5fb0b0";
        if (["iso", "img", "dmg"].includes(ext)) return "#9aabbd";
        if (["sh", "fish", "bash", "zsh", "py", "js", "ts", "lua", "qml", "c", "cpp", "cc", "h", "hpp", "rs", "go", "java", "kt", "rb", "pl"].includes(ext)) return "#7bb0e0";
        return Appearance.colors.colOnLayer1;
    }

    // The GTK icon theme (Material-Originals) draws real, colourful folder and
    // mimetype icons -- the same ones Nautilus shows. Its SVGs are clean and render
    // in Qt, unlike breeze's. Resolved by file path; the glyph is the last-resort
    // fallback for anything the theme is missing.
    // Directories.home already carries the file:// scheme; strip it and add exactly
    // one, or the url comes out file://file:///... and nothing loads.
    readonly property string iconThemeBase: `file://${FileUtils.trimFileProtocol(String(Directories.home))}/.local/share/icons/Material-Originals/scalable`

    function mimeIconName(name) {
        const ext = root.fileExt(name);
        const archive = ["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "zst", "lz", "lzma"];
        const audio = ["mp3", "ogg", "wav", "flac", "m4a", "opus", "aac", "mid", "wma"];
        const video = ["mp4", "mkv", "webm", "mov", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "ts", "3gp"];
        const image = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "ico", "tif", "tiff"];
        const script = ["sh", "fish", "bash", "zsh", "py", "js", "ts", "lua", "qml", "c", "cpp", "cc", "h", "hpp", "rs", "go", "java", "kt", "rb", "pl"];
        const text = ["txt", "md", "rtf", "log", "csv", "json", "yaml", "yml", "toml", "xml", "html", "htm", "css", "ini", "conf"];
        const exe = ["exe", "bin", "run", "msi", "app"];
        const disk = ["iso", "img", "dmg"];
        if (ext === "pdf") return "application-pdf";
        if (ext === "appimage") return "application-vnd.appimage";
        if (archive.includes(ext)) return "application-x-archive";
        if (audio.includes(ext)) return "audio-x-generic";
        if (video.includes(ext)) return "video-x-generic";
        if (image.includes(ext)) return "image-x-generic";
        if (exe.includes(ext)) return "application-x-executable";
        if (disk.includes(ext)) return "application-x-cd-image";
        if (script.includes(ext)) return "text-x-script";
        if (text.includes(ext)) return "text-x-generic";
        return "application-x-generic";
    }

    function themeIconUrl(name, isDir) {
        if (isDir)
            return `${root.iconThemeBase}/places/folder.svg`;
        return `${root.iconThemeBase}/mimetypes/${root.mimeIconName(name)}.svg`;
    }

    function acceptLabel() {
        if (root.req.acceptLabel && root.req.acceptLabel.length > 0)
            return root.req.acceptLabel;
        if (root.mode === "save")
            return Translation.tr("Save");
        if (root.directory)
            return Translation.tr("Choose");
        return Translation.tr("Open");
    }

    function canAccept() {
        if (root.mode === "save")
            return nameField.text.trim().length > 0;
        if (root.directory)
            return true;
        return root.selectedUrls.length > 0;
    }

    function accept() {
        if (!root.canAccept())
            return;
        // File-open mode: "Open" on a single selected folder enters it (Nautilus-style)
        // -- a folder is not a valid file answer. With a multi-selection, submit it all.
        if (root.mode === "open" && !root.directory && root.selectedUrls.length === 1
                && root.selectedInfo && root.selectedInfo.isDir) {
            root.enterFolder(Qt.resolvedUrl(root.selectedInfo.url));
            return;
        }
        let uris = [];
        if (root.mode === "save")
            uris = [`${String(folderModel.folder)}/${encodeURIComponent(nameField.text.trim())}`];
        else if (root.directory)
            uris = [root.selectedUrl.length > 0 ? root.selectedUrl : String(folderModel.folder)];
        else
            uris = root.multiple ? root.selectedUrls.slice() : [root.selectedUrl];
        FilePicker.submit(uris);
    }

    function enterFolder(folderUrl) {
        // Only meaningful while browsing; during a search the view shows results, not
        // this folder, so its scroll would be wrong to stash.
        if (!root.searching())
            root.saveScroll();
        root.selectedUrl = "";
        root.selectedUrls = [];
        root.selectionAnchor = -1;
        root.selectedInfo = null;
        if (root.searchActive) {
            searchField.text = "";
            root.searchActive = false;
        }
        root.pendingScrollRestore = true;
        folderModel.folder = folderUrl;
    }

    // Shared by the list rows and the gallery cells. Multi mode: Ctrl-click toggles one
    // entry, Shift-click selects the range from the anchor, a plain click selects just
    // this one and drops the anchor here. Single mode: any click selects just this one.
    function selectEntry(info, index, mods) {
        const ctrl = root.multiple && (mods & Qt.ControlModifier) !== 0;
        const shift = root.multiple && (mods & Qt.ShiftModifier) !== 0;
        if (shift && root.selectionAnchor >= 0) {
            root.selectRange(root.selectionAnchor, index);
        } else if (ctrl) {
            const next = root.selectedUrls.slice();
            const at = next.indexOf(info.url);
            if (at === -1)
                next.push(info.url);
            else
                next.splice(at, 1);
            root.selectedUrls = next;
            root.selectionAnchor = index;
        } else {
            root.selectedUrls = [info.url];
            root.selectionAnchor = index;
        }
        root.selectedUrl = info.url;
        root.selectedInfo = info;
        if (root.mode === "save" && !info.isDir)
            nameField.text = info.name;
    }

    // Role access differs: FolderListModel is get(i, role), ListModel is get(i).role.
    function urlAt(i) {
        return root.searching() ? String(filteredModel.get(i).fileUrl)
                                : String(folderModel.get(i, "fileUrl"));
    }
    function selectRange(a, b) {
        const lo = Math.min(a, b);
        const hi = Math.max(a, b);
        const urls = [];
        for (let i = lo; i <= hi; i++)
            urls.push(root.urlAt(i));
        root.selectedUrls = urls;
    }
    function clearSelection() {
        root.selectedUrl = "";
        root.selectedUrls = [];
        root.selectionAnchor = -1;
        root.selectedInfo = null;
    }
    // Build the entry dict for a row index in the active model. FolderListModel is
    // get(i, role); the search ListModel is get(i).role.
    function entryAt(i) {
        let name, path, url, isDir, size, mod;
        if (root.searching()) {
            const o = filteredModel.get(i);
            name = o.fileName; path = o.filePath; url = String(o.fileUrl);
            isDir = o.fileIsDir === true; size = o.fileSize; mod = o.fileModified;
        } else {
            name = String(folderModel.get(i, "fileName"));
            path = String(folderModel.get(i, "filePath"));
            url = String(folderModel.get(i, "fileUrl"));
            isDir = folderModel.get(i, "fileIsDir") === true;
            size = folderModel.get(i, "fileSize");
            mod = folderModel.get(i, "fileModified");
        }
        return {
            "name": name, "path": path, "url": url, "isDir": isDir, "size": size, "modified": mod,
            "isImage": !isDir && Images.isThumbnailableByName(name) && !Images.isValidVideoByName(name),
            "isVideo": !isDir && Images.isValidVideoByName(name)
        };
    }
    // Rubber-band: select every entry the dragged rectangle covers, mapping the input
    // surface's coordinates to the uniform rows (list) or cells (grid).
    function marqueeSelect(a, b) {
        const view = root.currentView();
        const top = view.contentY + Math.min(a.y, b.y);
        const bot = view.contentY + Math.max(a.y, b.y);
        const urls = [];
        if (root.viewMode === 0) {
            const first = Math.max(0, Math.floor(top / root.rowHeight));
            const last = Math.min(view.count - 1, Math.floor(bot / root.rowHeight));
            for (let i = first; i <= last; i++)
                urls.push(root.urlAt(i));
        } else {
            const cols = Math.max(1, Math.floor(view.width / view.cellWidth));
            const c0 = Math.max(0, Math.floor(Math.min(a.x, b.x) / view.cellWidth));
            const c1 = Math.min(cols - 1, Math.floor(Math.max(a.x, b.x) / view.cellWidth));
            const r0 = Math.max(0, Math.floor(top / view.cellHeight));
            const r1 = Math.floor(bot / view.cellHeight);
            for (let r = r0; r <= r1; r++)
                for (let c = c0; c <= c1; c++) {
                    const idx = r * cols + c;
                    if (idx >= 0 && idx < view.count)
                        urls.push(root.urlAt(idx));
                }
        }
        root.selectedUrls = urls;
    }

    function openEntry(fileUrl, isDir, name) {
        if (isDir)
            root.enterFolder(fileUrl);
        else if (root.mode === "save")
            nameField.text = name;
        else
            root.accept();
    }

    function popupMenuFor(path, fileUrl, name, isDir) {
        ctxMenu.targetPath = path;
        ctxMenu.targetUrl = fileUrl;
        ctxMenu.targetName = name;
        ctxMenu.targetIsDir = isDir;
        ctxMenu.popup();
    }

    function sortBy(column) {
        if (root.sortColumn === column)
            root.sortDescending = !root.sortDescending;
        else {
            root.sortColumn = column;
            root.sortDescending = false;
        }
    }

    function currentView() {
        return root.viewMode === 0 ? fileList : fileGrid;
    }
    // Stash the current folder's scroll before leaving it; restore it (after the new
    // model settles) only when we arrived by back/forward/up, never on sort or filter.
    function saveScroll() {
        root.scrollMemory[String(folderModel.folder)] = root.currentView().contentY;
    }
    function restoreScroll() {
        const y = root.scrollMemory[String(folderModel.folder)] ?? 0;
        const view = root.currentView();
        Qt.callLater(() => view.contentY = y);
    }
    function goBack() {
        if (!root.searching())
            root.saveScroll();
        root.selectedUrl = "";
        root.selectedUrls = [];
        root.selectionAnchor = -1;
        root.selectedInfo = null;
        root.pendingScrollRestore = true;
        folderModel.navigateBack();
    }
    function goForward() {
        if (!root.searching())
            root.saveScroll();
        root.selectedUrl = "";
        root.selectedUrls = [];
        root.selectionAnchor = -1;
        root.selectedInfo = null;
        root.pendingScrollRestore = true;
        folderModel.navigateForward();
    }

    function searching() {
        return root.searchActive && root.searchText.length > 0;
    }
    // Search is RECURSIVE: matches in this folder and every subfolder under it. That is
    // beyond FolderListModel (one folder only), so it shells out to `find` via a
    // debounced Process; results land in filteredModel, which the views read while
    // searching. The debounce keeps keystrokes from spawning a find each.
    function rebuildFiltered() {
        if (!root.searching()) {
            searchDebounce.stop();
            filteredModel.clear();
            return;
        }
        searchDebounce.restart();
    }
    // Parse `find -printf '%y\t%s\t%T@\t%p'` lines into the model; name is the path
    // relative to the searched folder so a nested hit shows where it lives.
    function applySearchResults(text) {
        filteredModel.clear();
        if (!root.searching())
            return;
        const base = FileUtils.trimFileProtocol(String(folderModel.folder)).replace(/\/+$/, "");
        const lines = (text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0)
                continue;
            const parts = line.split("\t");
            if (parts.length < 4)
                continue;
            const path = parts.slice(3).join("\t");
            if (path === base)
                continue;
            const mtime = parseFloat(parts[2]) || 0;
            const rel = path.indexOf(base + "/") === 0 ? path.slice(base.length + 1) : path;
            filteredModel.append({
                "fileName": rel,
                "filePath": path,
                "fileUrl": "file://" + path,
                "fileIsDir": parts[0] === "d",
                "fileSize": parseInt(parts[1], 10) || 0,
                "fileModified": mtime > 0 ? new Date(mtime * 1000) : new Date(0)
            });
        }
    }

    // Nautilus/GTK stores one bookmark per line: "<file-uri> [display name]".
    function parseBookmarks() {
        const txt = bookmarksFile.text();
        const out = [];
        if (txt && txt.length > 0) {
            const lines = txt.split("\n");
            for (let i = 0; i < lines.length; i++) {
                const t = lines[i].trim();
                if (t.length === 0 || t.indexOf("file://") !== 0)
                    continue;
                const sp = t.indexOf(" ");
                const uri = sp >= 0 ? t.slice(0, sp) : t;
                let name = sp >= 0 ? t.slice(sp + 1).trim() : "";
                if (name.length === 0) {
                    const p = FileUtils.trimFileProtocol(uri).replace(/\/+$/, "");
                    const parts = p.split("/");
                    name = parts[parts.length - 1] || p;
                }
                out.push({ "name": name, "path": uri });
            }
        }
        root.bookmarks = out;
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton)
            root.goBack();
        else if (event.button === Qt.ForwardButton)
            root.goForward();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.searchActive) {
                searchField.text = "";
                root.searchActive = false;
            } else
                FilePicker.cancel();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.mode !== "save") {
            root.accept();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            root.searchActive = !root.searchActive;
            if (root.searchActive)
                searchField.forceActiveFocus();
            else
                searchField.text = "";
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
            root.enterFolder(folderModel.parentFolder);
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) {
            root.goBack();
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) {
            root.goForward();
            event.accepted = true;
        } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
            // Type-ahead: a printable key opens the search field and starts filtering.
            root.searchActive = true;
            searchField.text += event.text;
            searchField.forceActiveFocus();
            event.accepted = true;
        }
    }

    Connections {
        target: GlobalStates
        function onFilePickerOpenChanged() {
            if (GlobalStates.filePickerOpen)
                root.forceActiveFocus();
        }
    }
    Component.onCompleted: {
        root.forceActiveFocus();
        if (root.mode === "save")
            nameField.text = root.req.saveName ?? "";
        // No folder requested -> reopen where the last pick left off, if we have one.
        if ((!root.req.currentFolder || root.req.currentFolder.length === 0) && FilePicker.lastFolder.length > 0)
            folderModel.folder = Qt.resolvedUrl(FilePicker.lastFolder);
    }

    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl((root.req.currentFolder && root.req.currentFolder.length > 0) ? root.req.currentFolder : Directories.home)
        showDirs: true
        showDirsFirst: root.foldersFirst
        showDotAndDotDot: false
        showHidden: root.showHiddenFiles
        showFiles: !root.directory
        sortReversed: root.sortDescending
        sortField: root.sortColumn === 1 ? FolderListModel.Size
            : root.sortColumn === 2 ? FolderListModel.Time
            : FolderListModel.Name
        caseSensitive: false
        // Only the format filter here. Search is done in rebuildFiltered() so it can
        // also hide folders, which nameFilters cannot.
        nameFilters: {
            const f = root.filters[root.currentFilterIndex];
            return (f && f.patterns && f.patterns.length > 0) ? f.patterns : ["*"];
        }
    }

    // Recursive search results (this folder + subfolders), shown while searching.
    ListModel { id: filteredModel }

    Timer {
        id: searchDebounce
        interval: 180
        onTriggered: searchProc.runSearch()
    }

    Process {
        id: searchProc
        property string dir: ""
        property string pattern: ""
        function runSearch() {
            if (!root.searching()) {
                filteredModel.clear();
                return;
            }
            searchProc.running = false;
            searchProc.dir = FileUtils.trimFileProtocol(String(folderModel.folder));
            searchProc.pattern = "*" + root.searchText + "*";
            searchProc.running = true;
        }
        // timeout + head bound a search over a huge tree; -iname matches basenames
        // case-insensitively at any depth. Args are passed positionally, not spliced
        // into the script, so a query with shell metacharacters is harmless.
        command: ["bash", "-c",
            `timeout 6 find "$1" -iname "$2" -printf '%y\\t%s\\t%T@\\t%p\\n' 2>/dev/null | head -n 1000`,
            "yuki-search", searchProc.dir, searchProc.pattern]
        stdout: StdioCollector {
            id: searchCollector
            onStreamFinished: root.applySearchResults(searchCollector.text)
        }
    }

    // Remember the folder for the next open, and restore scroll after a back/forward/up.
    Connections {
        target: folderModel
        function onStatusChanged() {
            if (folderModel.status === FolderListModel.Ready) {
                FilePicker.lastFolder = String(folderModel.folder);
                if (root.searching())
                    root.rebuildFiltered();
                if (root.pendingScrollRestore) {
                    root.pendingScrollRestore = false;
                    root.restoreScroll();
                }
            } else if (folderModel.status !== FolderListModel.Loading) {
                // A terminal non-ready state (e.g. an unreadable folder): drop the
                // pending restore so it can't fire stale on the next good load.
                root.pendingScrollRestore = false;
            }
        }
    }

    // The user's Nautilus bookmarks, live: edits in the file manager show up here too.
    FileView {
        id: bookmarksFile
        path: `${FileUtils.trimFileProtocol(String(Directories.home))}/.config/gtk-3.0/bookmarks`
        watchChanges: true
        onFileChanged: bookmarksFile.reload()
        onLoaded: root.parseBookmarks()
        onLoadFailed: root.bookmarks = []
    }

    // A column header cell: label, optional sort arrow, click to sort.
    component HeaderCell: MouseArea {
        id: headerCell
        property string label
        property int column: 0
        property int align: Text.AlignLeft
        implicitHeight: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.sortBy(headerCell.column)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 2
            layoutDirection: headerCell.align === Text.AlignRight ? Qt.RightToLeft : Qt.LeftToRight
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: headerCell.align
                text: headerCell.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.sortColumn === headerCell.column ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                visible: root.sortColumn === headerCell.column
                text: root.sortDescending ? "arrow_downward" : "arrow_upward"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }

    component NavButton: RippleButton {
        id: navButton
        property string symbol
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: navButton.symbol
            iconSize: 20
            color: Appearance.colors.colOnLayer0
        }
    }

    // File/folder icon: colourful theme icon by extension, a never-blank glyph
    // fallback, image thumbnails, and one extracted frame for videos. Shared by
    // the list rows and the gallery cells so both render identically.
    component FileEntryIcon: Item {
        id: fic
        property string entryName: ""
        property string entryPath: ""
        property bool entryIsDir: false
        property int size: 24
        readonly property bool isImage: !fic.entryIsDir
            && Images.isThumbnailableByName(fic.entryName)
            && !Images.isValidVideoByName(fic.entryName)
        readonly property bool isVideo: !fic.entryIsDir
            && Images.isValidVideoByName(fic.entryName)
        implicitWidth: fic.size
        implicitHeight: fic.size

        // Real theme icon (folder / mimetype). Hidden for media -- the thumbnail
        // takes those -- and when the theme has no such icon (then the glyph shows).
        Image {
            id: themeIcon
            anchors.centerIn: parent
            width: fic.size
            height: fic.size
            sourceSize.width: fic.size * 2
            sourceSize.height: fic.size * 2
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready && !fic.isImage && !fic.isVideo
            source: root.themeIconUrl(fic.entryName, fic.entryIsDir)
        }
        // Glyph: media placeholder (until the thumbnail builds) and last-resort
        // fallback when the theme icon is missing. Never blank. Distance-field text
        // stays clean at gallery sizes where the native rasteriser leaves a seam.
        MaterialSymbol {
            anchors.centerIn: parent
            visible: fic.isImage || fic.isVideo || themeIcon.status !== Image.Ready
            text: root.categoryGlyph(fic.entryName, fic.entryIsDir)
            iconSize: fic.size
            fill: 1
            renderType: Text.QtRendering
            color: root.categoryColor(fic.entryName, fic.entryIsDir)
        }
        // Images: crisp cached thumbnail.
        Loader {
            anchors.fill: parent
            active: fic.isImage
            sourceComponent: ThumbnailImage {
                generateThumbnail: true
                sourcePath: fic.entryPath
                fillMode: Image.PreserveAspectCrop
            }
        }
        // Videos: one extracted frame (ffmpegthumbnailer).
        Loader {
            anchors.fill: parent
            active: fic.isVideo
            sourceComponent: Item {
                ThumbnailImage {
                    id: vThumb
                    anchors.fill: parent
                    generateThumbnail: false
                    thumbnailSizeName: "large"
                    sourcePath: fic.entryPath
                    fillMode: Image.PreserveAspectCrop
                }
                Process {
                    id: vGen
                    command: ["bash", "-c",
                        '[ -f "$2" ] || ffmpegthumbnailer -i "$1" -o "$2" -s 256 -q 6 2>/dev/null',
                        "yuki-vthumb", fic.entryPath,
                        FileUtils.trimFileProtocol(vThumb.thumbnailPath)]
                    onExited: {
                        vThumb.source = "";
                        vThumb.source = vThumb.thumbnailPath;
                    }
                }
                Component.onCompleted: vGen.running = true
                Connections {
                    target: vThumb
                    function onSourcePathChanged() {
                        vGen.running = false;
                        vGen.running = true;
                    }
                }
            }
        }
    }

    // Right-click context menu on a row.
    component CtxItem: MenuItem {
        id: ctxItem
        property bool showCheck: false
        implicitHeight: 34
        implicitWidth: 224
        contentItem: RowLayout {
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                text: ctxItem.text
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                Layout.rightMargin: 10
                visible: ctxItem.showCheck
                text: "check"
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
        }
        background: Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Appearance.rounding.verysmall
            color: ctxItem.highlighted ? Appearance.colors.colLayer2Hover : "transparent"
        }
    }

    Menu {
        id: ctxMenu
        property string targetPath: ""
        property string targetUrl: ""
        property string targetName: ""
        property bool targetIsDir: false
        padding: 6

        background: Rectangle {
            implicitWidth: 208
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.small
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        CtxItem {
            text: ctxMenu.targetIsDir ? Translation.tr("Open")
                : (root.mode === "save" ? Translation.tr("Use this name") : Translation.tr("Open"))
            onTriggered: {
                if (ctxMenu.targetIsDir)
                    root.enterFolder(ctxMenu.targetUrl);
                else if (root.mode === "save")
                    nameField.text = ctxMenu.targetName;
                else {
                    // Return this file: make it the whole selection and drop any stale
                    // folder selection so accept()'s folder-enter guard can't fire.
                    root.selectedUrl = ctxMenu.targetUrl;
                    root.selectedUrls = [ctxMenu.targetUrl];
                    root.selectedInfo = null;
                    root.accept();
                }
            }
        }
        CtxItem {
            text: Translation.tr("Copy path")
            onTriggered: Quickshell.clipboardText = ctxMenu.targetPath
        }
        CtxItem {
            text: Translation.tr("Copy name")
            onTriggered: Quickshell.clipboardText = ctxMenu.targetName
        }
        CtxItem {
            text: Translation.tr("Open in file manager")
            onTriggered: Quickshell.execDetached(["xdg-open", FileUtils.trimFileProtocol(String(folderModel.folder))])
        }
        MenuSeparator {
            padding: 6
            contentItem: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }
        CtxItem {
            text: Translation.tr("Show hidden files")
            showCheck: root.showHiddenFiles
            onTriggered: root.showHiddenFiles = !root.showHiddenFiles
        }
        CtxItem {
            text: Translation.tr("Folders first")
            showCheck: root.foldersFirst
            onTriggered: root.foldersFirst = !root.foldersFirst
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colLayer0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Title
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol {
                    text: root.headerIcon
                    iconSize: 26
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.titleText
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.weight: 550
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
            }

            // Toolbar: navigation + address / search + view controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                NavButton {
                    symbol: "arrow_back"
                    enabled: folderModel.currentFolderHistoryIndex > 0
                    onClicked: root.goBack()
                }
                NavButton {
                    symbol: "arrow_forward"
                    enabled: folderModel.currentFolderHistoryIndex < folderModel.folderHistory.length - 1
                    onClicked: root.goForward()
                }
                NavButton {
                    symbol: "arrow_upward"
                    onClicked: root.enterFolder(folderModel.parentFolder)
                }
                AddressBar {
                    visible: !root.searchActive
                    Layout.fillWidth: true
                    radius: Appearance.rounding.small
                    directory: FileUtils.trimFileProtocol(String(folderModel.folder))
                    onNavigateToDirectory: path => root.enterFolder(Qt.resolvedUrl(path.length === 0 ? "/" : path))
                }
                ToolbarTextField {
                    id: searchField
                    visible: root.searchActive
                    Layout.fillWidth: true
                    // The widget defaults to Layout.fillHeight, which balloons into a
                    // giant pill in this toolbar row; pin it to the button height.
                    Layout.fillHeight: false
                    Layout.preferredHeight: 38
                    Layout.maximumHeight: 38
                    placeholderText: Translation.tr("Search this folder")
                    // Emptying the field (backspacing it all out) closes search, so a
                    // cleared search does not leave a stray box sitting in the toolbar.
                    onTextChanged: {
                        root.searchText = text;
                        if (text.length === 0 && root.searchActive) {
                            root.searchActive = false;
                            root.forceActiveFocus();
                        } else {
                            root.rebuildFiltered();
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            text = "";
                            root.searchActive = false;
                            root.forceActiveFocus();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            root.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                }
                NavButton {
                    symbol: "search"
                    toggled: root.searchActive
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    onClicked: {
                        root.searchActive = !root.searchActive;
                        if (root.searchActive) {
                            searchField.forceActiveFocus();
                        } else {
                            searchField.text = "";
                            root.forceActiveFocus();
                        }
                    }
                }
                NavButton {
                    symbol: root.viewMode === 0 ? "grid_view" : "view_list"
                    onClicked: root.viewMode = root.viewMode === 0 ? 1 : 0
                }
                NavButton {
                    symbol: "zoom_out"
                    enabled: root.viewMode === 0 ? root.iconSize > 16 : root.gridIconSize > 48
                    onClicked: {
                        if (root.viewMode === 0)
                            root.iconSize = Math.max(16, root.iconSize - 8);
                        else
                            root.gridIconSize = Math.max(48, root.gridIconSize - 12);
                    }
                }
                NavButton {
                    symbol: "zoom_in"
                    enabled: root.viewMode === 0 ? root.iconSize < 48 : root.gridIconSize < 128
                    onClicked: {
                        if (root.viewMode === 0)
                            root.iconSize = Math.min(48, root.iconSize + 8);
                        else
                            root.gridIconSize = Math.min(128, root.gridIconSize + 12);
                    }
                }
            }

            // Body: places | (column header + list/grid) | preview
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Places
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 168
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        interactive: true
                        spacing: 2
                        model: root.placesModel
                        ScrollBar.vertical: StyledScrollBar {}
                        delegate: Item {
                            id: placeItem
                            required property var modelData
                            width: ListView.view ? ListView.view.width : implicitWidth
                            implicitHeight: (placeItem.modelData.header ?? false) ? 32 : 36

                            // Section header (e.g. "Bookmarks"), not clickable.
                            StyledText {
                                visible: placeItem.modelData.header ?? false
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                text: placeItem.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: 600
                                color: Appearance.colors.colSubtext
                            }

                            RippleButton {
                                id: placeBtn
                                visible: !(placeItem.modelData.header ?? false)
                                anchors.fill: parent
                                buttonRadius: Appearance.rounding.small
                                toggled: placeBtn.visible && FileUtils.trimFileProtocol(String(folderModel.folder)).replace(/\/+$/, "") === FileUtils.trimFileProtocol(String(placeItem.modelData.path)).replace(/\/+$/, "")
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                onClicked: root.enterFolder(Qt.resolvedUrl(placeItem.modelData.path))
                                contentItem: RowLayout {
                                    spacing: 10
                                    MaterialSymbol {
                                        Layout.leftMargin: 8
                                        text: placeItem.modelData.icon
                                        iconSize: Appearance.font.pixelSize.large
                                        fill: placeBtn.toggled ? 1 : 0
                                        color: placeBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 8
                                        horizontalAlignment: Text.AlignLeft
                                        text: placeItem.modelData.name
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: placeBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                }

                // Column header + file list/grid
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Column header (list view only)
                    RowLayout {
                        visible: root.viewMode === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10 + (fileList.ScrollBar.vertical?.width ?? 0)
                        spacing: 12
                        HeaderCell {
                            Layout.fillWidth: true
                            label: Translation.tr("Name")
                            column: 0
                        }
                        HeaderCell {
                            visible: !root.directory
                            Layout.preferredWidth: root.sizeColumnWidth
                            label: Translation.tr("Size")
                            column: 1
                            align: Text.AlignRight
                        }
                        HeaderCell {
                            Layout.preferredWidth: root.dateColumnWidth
                            label: Translation.tr("Modified")
                            column: 2
                        }
                    }

                    Rectangle {
                        visible: root.viewMode === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Appearance.colors.colOutlineVariant
                    }

                    // Both views live here; only one is visible at a time.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 4

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.searching()
                                ? (filteredModel.count === 0)
                                : (folderModel.count === 0 && folderModel.status === FolderListModel.Ready)
                            text: root.searching()
                                ? ((searchProc.running || searchDebounce.running) ? Translation.tr("Searching…") : Translation.tr("No matches"))
                                : Translation.tr("Empty folder")
                            color: Appearance.colors.colSubtext
                        }

                        ListView {
                            id: fileList
                            anchors.fill: parent
                            visible: root.viewMode === 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.searching() ? filteredModel : folderModel
                            ScrollBar.vertical: StyledScrollBar {}

                            delegate: Rectangle {
                                id: rowItem
                                required property int index
                                required property string fileName
                                required property string filePath
                                required property url fileUrl
                                required property bool fileIsDir
                                required property real fileSize
                                required property date fileModified

                                readonly property bool selected: root.selectedUrls.indexOf(String(rowItem.fileUrl)) !== -1
                                readonly property bool hovered: root.hoveredIndex === rowItem.index
                                width: ListView.view.width
                                height: root.rowHeight
                                radius: Appearance.rounding.verysmall
                                color: rowItem.selected ? Appearance.colors.colSecondaryContainer
                                    : (rowItem.hovered ? Appearance.colors.colLayer2Hover : "transparent")
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 12

                                    FileEntryIcon {
                                        id: iconCell
                                        entryName: rowItem.fileName
                                        entryPath: rowItem.filePath
                                        entryIsDir: rowItem.fileIsDir
                                        size: root.iconSize
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: rowItem.fileName
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: rowItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        visible: !root.directory
                                        Layout.preferredWidth: root.sizeColumnWidth
                                        horizontalAlignment: Text.AlignRight
                                        text: rowItem.fileIsDir ? "" : root.humanSize(rowItem.fileSize)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: rowItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.preferredWidth: root.dateColumnWidth
                                        text: root.shortDate(rowItem.fileModified)
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: rowItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                    }
                                }

                            }
                        }

                        GridView {
                            id: fileGrid
                            anchors.fill: parent
                            visible: root.viewMode === 1
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cellWidth: root.gridIconSize + 40
                            cellHeight: root.gridIconSize + 56
                            model: root.searching() ? filteredModel : folderModel
                            ScrollBar.vertical: StyledScrollBar {}

                            delegate: Item {
                                id: cellItem
                                required property int index
                                required property string fileName
                                required property string filePath
                                required property url fileUrl
                                required property bool fileIsDir
                                required property real fileSize
                                required property date fileModified

                                readonly property bool selected: root.selectedUrls.indexOf(String(cellItem.fileUrl)) !== -1
                                readonly property bool hovered: root.hoveredIndex === cellItem.index
                                width: fileGrid.cellWidth
                                height: fileGrid.cellHeight

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: Appearance.rounding.small
                                    color: cellItem.selected ? Appearance.colors.colSecondaryContainer
                                        : (cellItem.hovered ? Appearance.colors.colLayer2Hover : "transparent")
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        FileEntryIcon {
                                            id: cellIcon
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.topMargin: 6
                                            entryName: cellItem.fileName
                                            entryPath: cellItem.filePath
                                            entryIsDir: cellItem.fileIsDir
                                            size: root.gridIconSize
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cellItem.fileName
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: cellItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                        }
                                        Item { Layout.fillHeight: true }
                                    }
                                }

                            }
                        }

                        // Single input surface over the views. Delegates carry no mouse
                        // of their own now: this hit-tests the row/cell under the cursor
                        // for hover, click (Ctrl/Shift aware), double click and the menu,
                        // and a left-drag draws the selection rectangle. The scrollbar
                        // strip on the right is left uncovered so it still works, and the
                        // wheel scrolls here (Ctrl+wheel zooms) since the drag is ours.
                        MouseArea {
                            id: viewInput
                            anchors.fill: parent
                            anchors.rightMargin: 16
                            z: 7
                            hoverEnabled: true
                            preventStealing: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: root.hoveredIndex >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

                            property real startX: 0
                            property real startY: 0
                            property bool dragging: false

                            function hit(x, y) {
                                const v = root.currentView();
                                return v.indexAt(v.contentX + x, v.contentY + y);
                            }

                            onWheel: wheel => {
                                if (wheel.modifiers & Qt.ControlModifier) {
                                    const dir = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0);
                                    if (dir === 0)
                                        return;
                                    if (root.viewMode === 0)
                                        root.iconSize = Math.max(16, Math.min(48, root.iconSize + dir * 4));
                                    else
                                        root.gridIconSize = Math.max(48, Math.min(128, root.gridIconSize + dir * 8));
                                    return;
                                }
                                const v = root.currentView();
                                const maxY = Math.max(0, v.contentHeight - v.height);
                                v.contentY = Math.max(0, Math.min(maxY, v.contentY - wheel.angleDelta.y));
                            }

                            onExited: root.hoveredIndex = -1
                            onPositionChanged: mouse => {
                                if (!viewInput.pressed) {
                                    root.hoveredIndex = viewInput.hit(mouse.x, mouse.y);
                                    return;
                                }
                                if (!(mouse.buttons & Qt.LeftButton))
                                    return;
                                if (!viewInput.dragging
                                        && (Math.abs(mouse.x - viewInput.startX) > 6 || Math.abs(mouse.y - viewInput.startY) > 6))
                                    viewInput.dragging = true;
                                if (viewInput.dragging)
                                    root.marqueeSelect(Qt.point(viewInput.startX, viewInput.startY), Qt.point(mouse.x, mouse.y));
                            }
                            onPressed: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    viewInput.startX = mouse.x;
                                    viewInput.startY = mouse.y;
                                    viewInput.dragging = false;
                                }
                            }
                            onReleased: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    const ri = viewInput.hit(mouse.x, mouse.y);
                                    if (ri >= 0) {
                                        const e = root.entryAt(ri);
                                        root.popupMenuFor(e.path, e.url, e.name, e.isDir);
                                    }
                                    return;
                                }
                                if (viewInput.dragging) {
                                    viewInput.dragging = false;
                                    return;
                                }
                                const idx = viewInput.hit(mouse.x, mouse.y);
                                if (idx >= 0)
                                    root.selectEntry(root.entryAt(idx), idx, mouse.modifiers);
                                else
                                    root.clearSelection();
                            }
                            onDoubleClicked: mouse => {
                                if (mouse.button !== Qt.LeftButton)
                                    return;
                                const idx = viewInput.hit(mouse.x, mouse.y);
                                if (idx < 0)
                                    return;
                                const e = root.entryAt(idx);
                                if (e.isDir)
                                    root.enterFolder(Qt.resolvedUrl(e.url));
                                else if (root.mode === "save")
                                    nameField.text = e.name;
                                else {
                                    root.selectedUrl = e.url;
                                    root.selectedUrls = [e.url];
                                    root.selectedInfo = e;
                                    root.accept();
                                }
                            }

                            Rectangle {
                                id: marqueeRect
                                visible: viewInput.dragging
                                x: Math.min(viewInput.startX, viewInput.mouseX)
                                y: Math.min(viewInput.startY, viewInput.mouseY)
                                width: Math.abs(viewInput.mouseX - viewInput.startX)
                                height: Math.abs(viewInput.mouseY - viewInput.startY)
                                radius: Appearance.rounding.verysmall
                                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18)
                                border.width: 1
                                border.color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }

                // Preview of the selected file.
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 220
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 172
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer2
                            clip: true

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: !root.singleSel
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedUrls.length > 1 ? "library_add_check" : "visibility"
                                    iconSize: 40
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.selectedUrls.length > 1
                                        ? Translation.tr("%1 selected").arg(root.selectedUrls.length)
                                        : Translation.tr("No selection")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: (root.selectedInfo?.isImage ?? false) && root.singleSel
                                sourceComponent: ThumbnailImage {
                                    generateThumbnail: true
                                    sourcePath: root.selectedInfo ? root.selectedInfo.path : ""
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                            Loader {
                                anchors.fill: parent
                                active: (root.selectedInfo?.isVideo ?? false) && root.singleSel
                                sourceComponent: Item {
                                    ThumbnailImage {
                                        id: videoThumb
                                        anchors.fill: parent
                                        generateThumbnail: false
                                        thumbnailSizeName: "large"
                                        sourcePath: root.selectedInfo ? root.selectedInfo.path : ""
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    // ThumbnailImage skips videos, so pull one frame with
                                    // ffmpegthumbnailer into the same cache path it reads.
                                    Process {
                                        id: videoThumbGen
                                        command: ["bash", "-c",
                                            '[ -f "$2" ] || ffmpegthumbnailer -i "$1" -o "$2" -s 256 -q 8 2>/dev/null',
                                            "yuki-vthumb",
                                            root.selectedInfo ? root.selectedInfo.path : "",
                                            FileUtils.trimFileProtocol(videoThumb.thumbnailPath)]
                                        onExited: {
                                            videoThumb.source = "";
                                            videoThumb.source = videoThumb.thumbnailPath;
                                        }
                                    }
                                    // Re-run for each newly selected video, not just the first.
                                    Component.onCompleted: videoThumbGen.running = true
                                    Connections {
                                        target: videoThumb
                                        function onSourcePathChanged() {
                                            videoThumbGen.running = false;
                                            videoThumbGen.running = true;
                                        }
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: videoThumb.status === Image.Ready
                                        implicitWidth: 40
                                        implicitHeight: 40
                                        radius: width / 2
                                        color: Qt.rgba(0, 0, 0, 0.45)
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            iconSize: 26
                                            fill: 1
                                            color: "white"
                                        }
                                    }
                                }
                            }
                            Loader {
                                anchors.fill: parent
                                active: root.singleSel && !!root.selectedInfo && !(root.selectedInfo.isImage) && !(root.selectedInfo.isVideo)
                                sourceComponent: Item {
                                    Image {
                                        id: previewThemeIcon
                                        anchors.centerIn: parent
                                        width: 104
                                        height: 104
                                        sourceSize.width: 208
                                        sourceSize.height: 208
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                        visible: status === Image.Ready
                                        source: root.selectedInfo ? root.themeIconUrl(root.selectedInfo.name, root.selectedInfo.isDir) : ""
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: previewThemeIcon.status !== Image.Ready
                                        text: root.selectedInfo ? root.categoryGlyph(root.selectedInfo.name, root.selectedInfo.isDir) : "draft"
                                        iconSize: 80
                                        fill: 1
                                        renderType: Text.QtRendering
                                        color: root.selectedInfo ? root.categoryColor(root.selectedInfo.name, root.selectedInfo.isDir) : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.singleSel
                            text: root.selectedInfo ? root.selectedInfo.name : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: 500
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.singleSel && !!root.selectedInfo && !root.selectedInfo.isDir
                            text: root.selectedInfo ? root.humanSize(root.selectedInfo.size) : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.singleSel
                            text: root.selectedInfo ? root.shortDate(root.selectedInfo.modified) : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // Save name
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: root.mode === "save"
                StyledText {
                    text: Translation.tr("Name")
                    color: Appearance.colors.colOnLayer0
                }
                MaterialTextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("File name")
                    onAccepted: root.accept()
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Format filter, compact, the way normal pickers put it.
                StyledComboBox {
                    visible: root.filters.length > 1
                    Layout.fillWidth: false
                    Layout.preferredWidth: 240
                    model: root.filters
                    textRole: "name"
                    onActivated: root.currentFilterIndex = currentIndex
                }
                Item { Layout.fillWidth: true }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: FilePicker.cancel()
                }
                DialogButton {
                    buttonText: root.acceptLabel()
                    enabled: root.canAccept()
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colText: Appearance.colors.colOnPrimary
                    onClicked: root.accept()
                }
            }
        }
    }
}
