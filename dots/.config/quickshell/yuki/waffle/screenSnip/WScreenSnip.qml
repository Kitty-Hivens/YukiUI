pragma ComponentBehavior: Bound
import qs
import qs.core
import qs.core.functions
import qs.common.widgets
import qs.core.services
import qs.waffle
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    /// What the next panel will be opened for, and on. Read once, when the panel is
    /// built: while it is up the panel owns its own mode, because its toolbar writes
    /// those properties directly and would break any binding held from out here.
    property var requestedMedia: WRegionSelectionPanel.MediaType.Image
    property var requestedImageAction: WRegionSelectionPanel.ImageAction.Copy
    property var requestedVideoAction: WRegionSelectionPanel.VideoAction.Record
    property var requestedScreen: null

    /// Every request builds a panel rather than retargeting the one that is up. The
    /// screen it covers, the capture it crops from and the name it hands focus back
    /// under are all fixed when it is created, so moving any of them underneath a
    /// live panel leaves the other two pointing at the screen it used to be on.
    function request(media, imageAction, videoAction) {
        root.requestedMedia = media;
        root.requestedImageAction = imageAction ?? WRegionSelectionPanel.ImageAction.Copy;
        root.requestedVideoAction = videoAction ?? WRegionSelectionPanel.VideoAction.Record;
        root.requestedScreen = Quickshell.screens.find(candidate => candidate.name === Hyprland.focusedMonitor?.name) ?? root.requestedScreen;
        if (WStates.regionSelectorOpen)
            WStates.regionSelectorOpen = false;
        WStates.regionSelectorOpen = true;
    }

    function dismiss() {
        WStates.regionSelectorOpen = false;
    }

    function screenshot() {
        root.request(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.Copy, null);
    }

    function ocr() {
        root.request(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.CharRecognition, null);
    }

    function search() {
        root.request(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.Search, null);
    }

    function record() {
        root.request(WRegionSelectionPanel.MediaType.Video, null, WRegionSelectionPanel.VideoAction.Record);
    }

    function recordWithSound() {
        root.request(WRegionSelectionPanel.MediaType.Video, null, WRegionSelectionPanel.VideoAction.RecordWithSound);
    }

    Loader {
        id: regionSelectorLoader
        active: WStates.regionSelectorOpen

        sourceComponent: WRegionSelectionPanel {
            // Taken as the panel is built and never rebound: the request cannot
            // change while this panel exists, because a new one destroys it first.
            screen: root.requestedScreen
            mediaType: root.requestedMedia
            imageAction: root.requestedImageAction
            videoAction: root.requestedVideoAction
            onClosed: root.dismiss()
        }
    }

    IpcHandler {
        target: "region"

        function screenshot(): void {
            root.screenshot();
        }
        function ocr(): void {
            root.ocr();
        }
        function record(): void {
            root.record();
        }
        function recordWithSound(): void {
            root.recordWithSound();
        }
        function search(): void {
            root.search();
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
