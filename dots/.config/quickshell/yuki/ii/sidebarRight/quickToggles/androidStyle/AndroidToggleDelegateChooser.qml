pragma ComponentBehavior: Bound
import qs.core.services
import qs.core
import qs.core.models.quickToggles
import qs.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    signal openGameModeDialog()

    /// The size a named toggle is configured at, or one cell for a toggle that is
    /// not in the panel at all -- the row of unused ones.
    function sizeForType(type: string): int {
        const configured = Config.options.sidebar.quickToggles.android.toggles.find(toggle => toggle?.type === type);
        return configured?.size ?? 1;
    }

    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "audio"; AndroidAudioToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openAudioOutputDialog()
        }
    } }

    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openBluetoothDialog()
        }
    } }

    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "darkMode"; AndroidDarkModeToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "easyEffects"; AndroidEasyEffectsToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openGameModeDialog()
        }
    } }

    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "mic"; AndroidMicToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openAudioInputDialog()
        }
    } }

    DelegateChoice { roleValue: "musicRecognition"; AndroidMusicRecognition {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "network"; AndroidNetworkToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openWifiDialog()
        }
    } }

    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "onScreenKeyboard"; AndroidOnScreenKeyboardToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {
        required property string modelData
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }

    // Whatever the shell has no branch of its own for is looked for among the
    // plugins. A name that answers to none of them -- a toggle whose plugin was
    // taken away, or a line put in the config by hand -- is drawn as a dead tile
    // rather than as nothing. Drawn as nothing it still held its place in the row,
    // and there was then no way left to take it out of the panel.
    DelegateChoice { AndroidQuickToggleButton {
        required property string modelData
        readonly property QuickToggleModel contributed: Plugins.quickToggle(modelData)
        toggleModel: contributed
        unknownType: !contributed
        buttonType: modelData
        editMode: root.editMode
        expandedSize: root.sizeForType(modelData) > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: root.sizeForType(modelData)
    } }
}
