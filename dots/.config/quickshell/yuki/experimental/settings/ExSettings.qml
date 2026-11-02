pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.experimental.input
import qs.experimental.looks

// The settings window's content, laid out as Windows 11 lays out its own: who
// is signed in, a search and the categories down the left, and on the right
// the path to the page, its title and the page itself.
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
            : page ? (page.component ?? "NotYetPage.qml")
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

    function open(key: string) {
        search.text = "";
        const page = catalogue.page(key);
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

    ShellLink {
        id: shellLink
        watching: root.Window.active
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Who is signed in, the search, and the categories.
        ColumnLayout {
            // Fixed: its rows fill its width, which would otherwise have it
            // take the window's width from the page.
            Layout.fillWidth: false
            Layout.preferredWidth: 300
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            Layout.margins: ExLooks.spacing.m
            Layout.rightMargin: 0
            spacing: ExLooks.spacing.m

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                Layout.leftMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.m

                Rectangle {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: ExLooks.colors.tonal

                    ExText {
                        anchors.centerIn: parent
                        text: (root.username || "?").charAt(0).toUpperCase()
                        font.pixelSize: 24
                        font.weight: 600
                        color: ExLooks.colors.tonalInk
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ExText {
                        Layout.fillWidth: true
                        text: root.username
                        font.weight: ExLooks.font.weightTitle
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: Translation.tr("Local account")
                        role: "caption"
                        dim: true
                    }
                }
            }

            ExTextField {
                id: search

                Layout.fillWidth: true
                glyph: "search"
                placeholder: Translation.tr("Find a setting")
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                    implicitHeight: 40
                    hoverEnabled: true
                    onClicked: root.open(navItem.modelData.key)

                    background: Rectangle {
                        radius: ExLooks.radius.menuItem
                        color: navItem.here ? ExLooks.colors.tonal : "transparent"

                        ExStateLayer {
                            ink: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            hovered: navItem.hovered
                            pressed: navItem.down
                        }
                    }
                    contentItem: RowLayout {
                        spacing: ExLooks.spacing.m

                        ExGlyph {
                            Layout.leftMargin: ExLooks.spacing.m
                            text: navItem.modelData.glyph
                            size: 20
                            fill: navItem.here ? 1 : 0
                            color: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: navItem.modelData.name
                            color: navItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            font.weight: navItem.here ? ExLooks.font.weightLabel : ExLooks.font.weightBody
                        }
                    }
                }
            }
        }

        // The path, the title and the page.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Category, then the page within it, the category going back.
            // Comes in with the page under it.
            Row {
                opacity: root.arrival
                transform: Translate {
                    x: root.arrivalX
                    y: root.arrivalY
                }
                Layout.leftMargin: ExLooks.spacing.xl + ExLooks.spacing.l
                Layout.topMargin: ExLooks.spacing.xl
                Layout.bottomMargin: ExLooks.spacing.m
                spacing: ExLooks.spacing.s

                AbstractButton {
                    id: crumb

                    ExPrimaryOnly {
                        z: 1
                    }

                    readonly property bool leads: root.page !== null && !root.shownSearching

                    anchors.verticalCenter: parent.verticalCenter
                    enabled: crumb.leads
                    hoverEnabled: true
                    onClicked: root.open(root.categoryKey)

                    contentItem: ExText {
                        text: root.shownSearching ? Translation.tr("Search") : (root.category?.name ?? "")
                        font.pixelSize: 28
                        font.weight: ExLooks.font.weightTitle
                        color: crumb.leads && !crumb.hovered ? ExLooks.colors.textDim : ExLooks.colors.text
                    }
                    background: null
                }
                ExGlyph {
                    visible: crumb.leads
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    size: 24
                    color: ExLooks.colors.textDim
                }
                ExText {
                    visible: crumb.leads
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.page?.name ?? ""
                    font.pixelSize: 28
                    font.weight: ExLooks.font.weightTitle
                }
            }

            Flickable {
                id: scroller

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: pageHolder.implicitHeight + ExLooks.spacing.xl
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // No wider than a line can be read at, as on Windows.
                Item {
                    id: pageHolder

                    x: ExLooks.spacing.xl + ExLooks.spacing.l
                    width: Math.min(1000, scroller.width - 2 * x)
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
    }

    ExNavigationButtons {
        z: 1
        onBack: root.back()
        onForward: root.forward()
    }
}
