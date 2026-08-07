pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
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

    /// What the selection will be used for, held here rather than pushed into the
    /// panel after it exists: pushed in, a mode set while the panel was already
    /// open never arrived, and the plain screenshot key could not take the panel
    /// back out of the mode a previous key had left it in.
    property var mediaType: WRegionSelectionPanel.MediaType.Image
    property var imageAction: WRegionSelectionPanel.ImageAction.Copy
    property var videoAction: WRegionSelectionPanel.VideoAction.Record

    /// The screen the key was pressed on. The panel covers one screen, and the one
    /// it should cover is the one being looked at.
    property var targetScreen: null

    function selectOn(media, image, video) {
        root.mediaType = media;
        root.imageAction = image ?? root.imageAction;
        root.videoAction = video ?? root.videoAction;
        root.targetScreen = Quickshell.screens.find(candidate => candidate.name === Hyprland.focusedMonitor?.name) ?? null;
        GlobalStates.regionSelectorOpen = true;
    }

    function dismiss() {
        GlobalStates.regionSelectorOpen = false;
    }

    function screenshot() {
        root.selectOn(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.Copy, null);
    }

    function ocr() {
        root.selectOn(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.CharRecognition, null);
    }

    function search() {
        root.selectOn(WRegionSelectionPanel.MediaType.Image, WRegionSelectionPanel.ImageAction.Search, null);
    }

    function record() {
        root.selectOn(WRegionSelectionPanel.MediaType.Video, null, WRegionSelectionPanel.VideoAction.Record);
    }

    function recordWithSound() {
        root.selectOn(WRegionSelectionPanel.MediaType.Video, null, WRegionSelectionPanel.VideoAction.RecordWithSound);
    }

    Loader {
        id: regionSelectorLoader
        active: GlobalStates.regionSelectorOpen

        sourceComponent: WRegionSelectionPanel {
            screen: root.targetScreen
            mediaType: root.mediaType
            imageAction: root.imageAction
            videoAction: root.videoAction
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
