pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.ii.systemSettings
import qs.common.widgets
import qs.common

/**
 * What is installed under `plugins/`, what of it runs, and the settings each one
 * declared.
 *
 * The registry already knew all three; nothing could ask it. Turning a plugin
 * off meant editing the shell's config by hand, configuring one meant editing a
 * second file by hand, and a plugin refused for a broken manifest looked exactly
 * like a plugin nobody had installed.
 */
Item {
    id: root

    readonly property list<var> entries: Plugins.entries
    readonly property int onCount: root.entries.filter(entry => !Plugins.isDisabled(entry.id)).length
    readonly property int brokenCount: root.entries.filter(entry => (entry.problem ?? "").length > 0).length

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            // Hidden while there is nothing installed: with no plugins it counts
            // none of them and names a folder, which is what the empty page below
            // says better and with a way to open it.
            SystemCard {
                Layout.fillWidth: true
                visible: root.entries.length > 0
                icon: "extension"
                title: Translation.tr("%1 of %2 on").arg(root.onCount).arg(root.entries.length)
                subtitle: Translation.tr("A plugin switched off is never built, so it cannot start a process or claim a shortcut while it is off")

                FactRow {
                    label: Translation.tr("Installed in")
                    value: Plugins.pluginPath
                }
                FactRow {
                    label: Translation.tr("Not built")
                    value: root.brokenCount > 0 ? String(root.brokenCount) : ""
                }
            }

            PageHeading {
                visible: root.entries.length > 0
                text: Translation.tr("Installed")
            }

            Repeater {
                model: root.entries

                delegate: SystemCard {
                    id: pluginCard
                    required property var modelData
                    Layout.fillWidth: true

                    PluginRow {
                        Layout.fillWidth: true
                        // Named rather than reached through `parent`: the card puts
                        // its content in an inner column, so the parent of this row
                        // is that column and not the delegate holding the data.
                        entry: pluginCard.modelData
                    }
                }
            }

            PageEmpty {
                visible: root.entries.length === 0
                roomLeft: pageFlick.height - 40
                symbol: "extension_off"
                heading: Translation.tr("No plugins installed")
                message: Translation.tr("Drop a directory with a manifest into the plugins folder and it appears here")
                actionIcon: "folder_open"
                actionText: Translation.tr("Open the folder")
                onActionClicked: Qt.openUrlExternally(`file://${Plugins.pluginPath}`)
            }
        }
    }
}
