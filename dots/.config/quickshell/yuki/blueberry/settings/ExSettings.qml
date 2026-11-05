pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.blueberry.input
import qs.blueberry.looks

// The settings window's content: who is signed in, a search and the
// categories down the left, and beside them the page under its path, its
// title and a line on how things stand.
Item {
    id: root

    /** The page to open on: a page's key or a category's, or empty for home. */
    property string startPage: ""
    /** Set by the display page, so closing the window knows there may be a
     *  layout waiting to be kept that has to be taken back. */
    property bool displaysTouched: false

    /**
     * Where the window is asked to be, which the list on the left marks at
     * once and the history keeps.
     */
    property string categoryKey: "home"
    /** A page within the category, or empty for the category's own page. */
    property string pageKey: ""
    readonly property string query: search.text.trim()
    /**
     * Taken from the environment, which has it from the start. Asked of
     * whoami, it arrived after the window was up, and the name and its letter
     * changed on screen.
     */
    readonly property string username: Quickshell.env("USER") || SystemInfo.username
    readonly property bool searching: root.query.length > 0

    /**
     * What is on show, which the title and the page itself read. It catches up
     * with the place asked for once that page is built, so the title never
     * names a page still being built over the one before it.
     */
    property string shownCategory: "home"
    property string shownPage: ""
    property bool shownSearching: false
    property var pending: null

    readonly property var category: catalogue.category(root.shownCategory)
    readonly property var page: root.shownPage.length > 0 ? catalogue.page(root.shownPage) : null

    /**
     * The pages the window has shown, oldest first, as { category, page }, and
     * which of them is on show, for going back and forward the way a browser
     * does. Opening a page from one gone back to drops those after it.
     */
    property var history: []
    property int historyIndex: -1

    function show(place) {
        root.entrance = root.entranceTo(place);
        root.categoryKey = place.category;
        root.pageKey = place.page;
        root.loadPage();
    }

    // Typing into the search shows its results, and clearing it the page
    // again. Typing more only narrows the results the page already shows.
    onSearchingChanged: {
        root.entrance = "up";
        root.loadPage();
    }

    /**
     * Two pages take turns: the next is built in the background while the
     * one on show stays, and comes in once it is whole. Built in one go, a
     * heavy page held the window blank for half a second and then appeared
     * at once, its coming in already over.
     */
    property int front: 0
    function loadPage() {
        const category = catalogue.category(root.categoryKey);
        const page = root.pageKey.length > 0 ? catalogue.page(root.pageKey) : null;
        root.pending = { category: root.categoryKey, page: root.pageKey, searching: root.searching };
        const url = Qt.resolvedUrl(root.searching ? "SearchPage.qml"
            : page ? (page.url ?? page.component ?? "NotYetPage.qml")
            : (category?.component ?? "CategoryPage.qml"));
        const back = root.front === 0 ? pageB : pageA;
        back.setSource(url, {
            settings: root,
            catalogue: catalogue,
            shell: shellLink
        });
    }
    /**
     * The page built and waiting for its first frame, or -1. Laid out and
     * drawn the first time is the costly part of a heavy page, the sound page
     * on the bench a good part of a second, and only a page on show pays it,
     * so it is shown all but transparent under the one on show until a frame
     * with it in has gone out. Swapped in before that, it came in blank and
     * stayed so while that frame was drawn.
     */
    property int warming: -1
    /**
     * A built page that says what it shows is still being read, a page of
     * devices or networks say, is held back until it has it, so it does not
     * come in empty and fill in. A page that says nothing is taken as whole.
     */
    property var waitingItem: null
    property int waitingWhich: -1
    function pageReady(which: int) {
        if (which === root.front)
            return;
        const item = (which === 0 ? pageA : pageB).item;
        if (item && item.ready === false) {
            root.waitingItem = item;
            root.waitingWhich = which;
            dataFallback.restart();
            return;
        }
        root.stage(which);
    }
    function dataIn() {
        const which = root.waitingWhich;
        root.waitingItem = null;
        root.waitingWhich = -1;
        dataFallback.stop();
        if (which >= 0)
            root.stage(which);
    }
    Connections {
        target: root.waitingItem
        ignoreUnknownSignals: true
        function onReadyChanged() {
            if (root.waitingItem?.ready)
                root.dataIn();
        }
    }
    // What never arrives does not keep the page away for good.
    Timer {
        id: dataFallback
        interval: 1500
        onTriggered: root.dataIn()
    }
    function stage(which: int) {
        if (which === root.front)
            return;
        root.warming = which;
        // The first page is shown with the window, which waits for it.
        if (!root.ready) {
            root.swapIn();
            return;
        }
        warmFallback.restart();
    }

    /**
     * The first page is in. The window is shown only from here, so it comes
     * up whole instead of filling in before the eyes.
     */
    property bool ready: false
    Connections {
        target: root.Window.window
        enabled: root.warming >= 0
        function onFrameSwapped() {
            root.swapIn();
        }
    }
    // Never left waiting for a frame that is not reported.
    Timer {
        id: warmFallback
        interval: 500
        onTriggered: root.swapIn()
    }
    function swapIn() {
        const which = root.warming;
        if (which < 0)
            return;
        root.warming = -1;
        warmFallback.stop();
        const leaving = which === 0 ? pageB : pageA;
        if (root.pending) {
            root.shownCategory = root.pending.category;
            root.shownPage = root.pending.page;
            root.shownSearching = root.pending.searching;
        }
        root.front = which;
        leaving.source = "";
        // A new page starts at its top, and comes in, but for the first,
        // which comes up with the window.
        scroller.contentY = 0;
        if (root.ready)
            root.arrive();
        root.ready = true;
    }

    /**
     * How the next page comes in, as Windows 11 moves its own: "in" from the
     * right going from a category into one of its pages, "out" from the left
     * coming back up to the category, "up" from below for anything else.
     */
    property string entrance: "up"
    function entranceTo(place): string {
        if (place.category === root.categoryKey) {
            if (place.page.length > 0 && root.pageKey.length === 0)
                return "in";
            if (place.page.length === 0 && root.pageKey.length > 0)
                return "out";
        }
        return "up";
    }

    /** From where the page comes in (0) to in place (1). */
    property real arrival: 1
    function arrive() {
        arrivalAnimation.stop();
        root.arrival = 0;
        arrivalAnimation.start();
    }
    NumberAnimation {
        id: arrivalAnimation
        target: root
        property: "arrival"
        to: 1
        duration: ExLooks.motion.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.decelerate
    }
    readonly property real arrivalX: (1 - root.arrival) * (root.entrance === "in" ? 40 : root.entrance === "out" ? -40 : 0)
    readonly property real arrivalY: (1 - root.arrival) * (root.entrance === "up" ? 24 : 0)

    /**
     * A page asked for before the plugins' manifests were read, so it may yet
     * turn out to be one of theirs. Asking for anything else forgets it.
     */
    property string awaitedPage: ""
    Connections {
        target: catalogue
        function onPagesChanged() {
            if (root.awaitedPage.length > 0 && catalogue.page(root.awaitedPage))
                root.open(root.awaitedPage);
        }
    }

    function open(key: string) {
        search.text = "";
        const page = catalogue.page(key);
        root.awaitedPage = key.length > 0 && !page && !catalogue.category(key) ? key : "";
        const place = page ? { category: page.category, page: page.key }
            : catalogue.category(key) ? { category: key, page: "" }
            : { category: "home", page: "" };
        const here = root.history[root.historyIndex];
        if (!here || here.category !== place.category || here.page !== place.page) {
            root.history = [...root.history.slice(0, root.historyIndex + 1), place];
            root.historyIndex = root.history.length - 1;
        }
        root.show(place);
    }

    /** Back a page, or out of a search first. */
    function back() {
        if (root.query.length > 0) {
            search.text = "";
            return;
        }
        if (root.historyIndex <= 0)
            return;
        root.historyIndex--;
        root.show(root.history[root.historyIndex]);
    }

    function forward() {
        if (root.historyIndex >= root.history.length - 1)
            return;
        root.historyIndex++;
        root.show(root.history[root.historyIndex]);
    }

    Component.onCompleted: root.open(root.startPage)

    SettingsCatalogue {
        id: catalogue
    }

    /** Who is signed in, for the rail and the account page. */
    readonly property AccountLink account: AccountLink {}

    ShellLink {
        id: shellLink
        watching: root.Window.active
    }

    readonly property var metrics: ExLooks.settings
    /** Home has no title over it: the machine itself stands at its top. */
    readonly property bool atHome: root.shownCategory === "home" && !root.shownSearching
    /** What the page on show says of how things stand, under its title. */
    readonly property string summary: (root.front === 0 ? pageA : pageB).item?.summary ?? ""

    /**
     * Escape, from the inside out: a search is cleared first, then the
     * window steps back a page, and only from where it started does it close.
     * Returns whether it was used here.
     */
    function stepOut(): bool {
        if (root.query.length > 0) {
            search.text = "";
            return true;
        }
        if (root.historyIndex > 0) {
            root.back();
            return true;
        }
        return false;
    }

    Shortcut {
        sequences: ["Alt+Left", StandardKey.Back]
        onActivated: root.back()
    }
    Shortcut {
        sequences: ["Alt+Right", StandardKey.Forward]
        onActivated: root.forward()
    }

    // What this window is, who is signed in, the search and the sections,
    // on the window's own tone. Every leading glyph down it stands on one
    // axis.
    Item {
        id: rail

        width: root.metrics.railWidth
        height: parent.height

        RowLayout {
            id: appTitle

            x: root.metrics.railAxis - root.metrics.railChip / 2
            y: root.metrics.contentTop
            width: parent.width - x - root.metrics.railPadding
            spacing: ExLooks.spacing.m

            SettingsChip {
                glyph: "settings"
                size: root.metrics.railChip
            }
            ExText {
                Layout.fillWidth: true
                text: Translation.tr("Settings")
                font.pixelSize: root.metrics.heading
                font.weight: ExLooks.font.weightTitle
            }
        }

        // Who is signed in, which leads to their account. Its plate shows only
        // under the pointer, and its avatar keeps to the rail's axis.
        AbstractButton {
            id: accountButton

            ExPrimaryOnly {
                z: 1
            }

            readonly property int inset: ExLooks.spacing.xs + 2

            x: root.metrics.railPadding
            y: appTitle.y + appTitle.height + ExLooks.spacing.xl - accountButton.inset
            width: parent.width - 2 * x
            implicitHeight: accountRow.implicitHeight + 2 * accountButton.inset
            hoverEnabled: true
            onClicked: root.open("account")

            ExFocusRing {
                anchors.margins: 0
                cornerRadius: root.metrics.controlRadius - 2
            }

            background: Rectangle {
                radius: root.metrics.controlRadius
                color: "transparent"

                ExStateLayer {
                    ink: ExLooks.colors.text
                    hovered: accountButton.hovered
                    pressed: accountButton.down
                }
            }
            contentItem: Item {
                RowLayout {
                    id: accountRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.metrics.railAxis - root.metrics.railPadding - root.metrics.avatar / 2
                    spacing: ExLooks.spacing.m

                    ExAvatar {
                        size: root.metrics.avatar
                        name: root.username
                        revision: root.account.pictureRevision
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        ExText {
                            Layout.fillWidth: true
                            text: root.account.realName.length > 0 ? root.account.realName : root.username
                            font.pixelSize: root.metrics.body
                            font.weight: ExLooks.font.weightTitle
                            elide: Text.ElideRight
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: Translation.tr("Local account")
                            font.pixelSize: root.metrics.small
                            dim: true
                        }
                    }
                }
            }
        }

        ExTextField {
            id: search

            x: root.metrics.railPadding
            y: accountButton.y + accountButton.height - accountButton.inset + ExLooks.spacing.l
            width: parent.width - 2 * x
            height: root.metrics.search
            radius: height / 2
            color: root.metrics.plate
            border.width: search.input.activeFocus ? 2 : 0
            border.color: ExLooks.colors.accent
            // The glyph on the rail's axis, as every glyph below it.
            inset: root.metrics.railAxis - 9 - x
            glyph: "search"
            placeholder: Translation.tr("Find a setting")
        }

        ListView {
            x: root.metrics.railPadding
            y: search.y + search.height + ExLooks.spacing.l
            width: parent.width - 2 * x
            height: parent.height - y - root.metrics.railPadding
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: catalogue.categories

            delegate: AbstractButton {
                id: navItem

                ExPrimaryOnly {
                    z: 1
                }

                required property var modelData
                readonly property bool here: root.query.length === 0 && navItem.modelData.key === root.categoryKey

                width: ListView.view.width
                implicitHeight: root.metrics.railItem
                hoverEnabled: true
                onClicked: root.open(navItem.modelData.key)

                ExFocusRing {
                    anchors.margins: 0
                    cornerRadius: root.metrics.controlRadius - 2
                }

                // The section on show is a tinted plate with its disc turned
                // to its colour, the way a tile in quick settings shows it is
                // on; the rest answer the pointer.
                background: Rectangle {
                    radius: root.metrics.controlRadius
                    color: navItem.here ? ExLooks.colors.tonal : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: ExLooks.motion.fast }
                    }

                    ExStateLayer {
                        ink: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                        hovered: navItem.hovered
                        pressed: navItem.down
                    }
                }
                contentItem: RowLayout {
                    spacing: ExLooks.spacing.m

                    SettingsChip {
                        Layout.leftMargin: root.metrics.railAxis - root.metrics.railPadding - root.metrics.railChip / 2
                        glyph: navItem.modelData.glyph
                        hue: navItem.modelData.hue ?? -1
                        size: root.metrics.railChip
                        inverted: navItem.here
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: navItem.modelData.name
                        font.pixelSize: root.metrics.body
                        font.weight: navItem.here ? ExLooks.font.weightTitle : ExLooks.font.weightBody
                        color: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                    }
                }
            }
        }
    }

    // The page's own area, a step lighter than the window, with the page's
    // way back, path and title held at its top.
    Rectangle {
        id: pane

        x: rail.width
        y: ExLooks.spacing.s
        width: parent.width - x - ExLooks.spacing.s
        height: parent.height - 2 * ExLooks.spacing.s
        radius: root.metrics.paneRadius
        color: root.metrics.pane

        // As wide as the window gives, and centred past what still reads as one
        // line from a label to its control.
        readonly property real column: Math.min(1600, pane.width - 2 * root.metrics.contentMargin)
        readonly property real columnX: Math.round((pane.width - pane.column) / 2)

        Item {
            id: headerBar

            visible: !root.atHome
            width: parent.width
            height: root.atHome ? 0 : header.y + header.height + ExLooks.spacing.l

            ColumnLayout {
                id: header

                x: pane.columnX
                // In line with the rail's title across the window.
                y: root.metrics.contentTop - pane.y
                width: pane.column
                spacing: 2
                opacity: root.arrival
                transform: Translate {
                    x: root.arrivalX
                    y: root.arrivalY
                }

                // The section over a page's title, which goes up to it.
                AbstractButton {
                    id: crumb

                    ExPrimaryOnly {
                        z: 1
                    }

                    readonly property bool leads: root.page !== null && !root.shownSearching

                    visible: crumb.leads
                    hoverEnabled: true
                    onClicked: root.open(root.categoryKey)

                    ExFocusRing {
                        cornerRadius: 2
                    }

                    background: null
                    contentItem: ExText {
                        text: root.category?.name ?? ""
                        font.pixelSize: root.metrics.small
                        font.weight: ExLooks.font.weightTitle
                        font.underline: crumb.hovered
                        color: ExLooks.colors.accentText
                    }
                }
                // Back, in front of the title it leaves, as tall as the title.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ExLooks.spacing.s

                    AbstractButton {
                        id: backButton

                        ExPrimaryOnly {
                            z: 1
                        }

                        visible: root.historyIndex > 0
                        // Its glyph's edge on the column's edge, under the path.
                        Layout.leftMargin: -6
                        implicitWidth: 36
                        implicitHeight: 36
                        hoverEnabled: true
                        onClicked: root.back()

                        ExFocusRing {
                            anchors.margins: 0
                            cornerRadius: root.metrics.controlRadius - 2
                        }

                        background: Rectangle {
                            radius: root.metrics.controlRadius
                            color: "transparent"

                            ExStateLayer {
                                ink: ExLooks.colors.text
                                hovered: backButton.hovered
                                pressed: backButton.down
                            }
                        }
                        contentItem: Item {
                            ExGlyph {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                size: 24
                            }
                        }
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: root.shownSearching ? Translation.tr("Results for \u201c%1\u201d").arg(root.query) : (root.page?.name ?? root.category?.name ?? "")
                        font.pixelSize: root.metrics.display
                        font.weight: ExLooks.font.weightTitle
                    }
                }
                ExText {
                    Layout.fillWidth: true
                    visible: root.summary.length > 0
                    text: root.summary
                    font.pixelSize: root.metrics.body
                    dim: true
                }
            }

            // Shown once the page runs under the title.
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.metrics.rule
                opacity: scroller.contentY > 1 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }
            }
        }

        Flickable {
            id: scroller

            y: headerBar.height
            width: parent.width
            height: parent.height - y
            clip: true
            contentHeight: pageHolder.y + pageHolder.implicitHeight + root.metrics.groupGap
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Item {
                id: pageHolder

                x: pane.columnX
                y: root.atHome ? root.metrics.contentTop - pane.y : ExLooks.spacing.s
                width: pane.column
                implicitHeight: (root.front === 0 ? pageA : pageB).item?.implicitHeight ?? 0
                opacity: root.arrival
                transform: Translate {
                    x: root.arrivalX
                    y: root.arrivalY
                }

                Loader {
                    id: pageA

                    width: parent.width
                    asynchronous: true
                    visible: root.front === 0 || root.warming === 0
                    opacity: root.warming === 0 ? 0.01 : 1
                    onLoaded: root.pageReady(0)
                }
                Loader {
                    id: pageB

                    width: parent.width
                    asynchronous: true
                    visible: root.front === 1 || root.warming === 1
                    opacity: root.warming === 1 ? 0.01 : 1
                    onLoaded: root.pageReady(1)
                }
            }
        }
    }

    ExNavigationButtons {
        z: 1
        onBack: root.back()
        onForward: root.forward()
    }
}
