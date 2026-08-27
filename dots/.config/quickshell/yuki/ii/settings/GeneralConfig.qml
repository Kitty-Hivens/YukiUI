import QtQuick
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.common.widgets

ContentPage {
    forceWidth: true


    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }
        ConfigRow {
            enabled: Config.options.audio.protection.enable
            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowedIncrease = value;
                }
            }
            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154 // pavucontrol allows up to 153%
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowed = value;
                }
            }
        }
    }



    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigRow {

            // AI policy
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("AI")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.ai
                    onSelected: newValue => {
                        Config.options.policies.ai = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Local only"),
                            icon: "sync_saved_locally",
                            value: 2
                        }
                    ]
                }
            }

            // Weeb policy
            ColumnLayout {

                ContentSubsectionLabel {
                    text: Translation.tr("Weeb")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.weeb
                    onSelected: newValue => {
                        Config.options.policies.weeb = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Closet"),
                            icon: "ev_shadow",
                            value: 2
                        }
                    ]
                }
            }
        }
    }



    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images copied from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }
}
