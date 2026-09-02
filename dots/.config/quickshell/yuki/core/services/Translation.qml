pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

Singleton {
    id: root

    property var translations: ({})
    property var generatedTranslations: ({})
    /**
     * What installed plugins say in the current language, merged into one map.
     *
     * A plugin ships English in its manifest and its QML, and its own
     * `translations/<language>.json` beside them. Without this a plugin could not
     * be translated at all -- the two maps above are the shell's own files, and
     * putting a plugin's strings in them would leave dead entries behind when it
     * is uninstalled.
     *
     * Replaced rather than mutated, so a binding reading it is told when a
     * plugin's file arrives.
     */
    property var pluginTranslations: ({})

    function takePluginTranslations(directory, data) {
        const next = Object.assign({}, root.pluginTranslations);
        // Keyed on nothing: the maps are flat and two plugins declaring the same
        // English string want the same Russian one. Last read wins, which for
        // identical strings is a distinction without a difference.
        Object.assign(next, data ?? {});
        root.pluginTranslations = next;
    }
    property var availableLanguages: ["en_US"]
    property var availableGeneratedLanguages: []
    property var allAvailableLanguages: {
        const combined = new Set([...root.availableLanguages, ...root.availableGeneratedLanguages]);
        return Array.from(combined).sort();
    }
    property bool isScanning: scanLanguagesProcess.running
    property bool isLoading: false
    property string translationKeepSuffix: "/*keep*/"
    property string translationsDir: Quickshell.shellPath("translations")
    property string generatedTranslationsDir: Directories.shellConfig + "/translations"

    property string languageCode: {
        // Until the config file has been read the adapter still answers with its
        // defaults, and answering from that switched the language twice on every
        // load -- once to the system locale, once to what the config actually asks
        // for -- reading four translation files to get there, half of them at a
        // path for a language nobody selected.
        if (!Config.ready)
            return "";

        var configLang = Config.options.language.ui ?? "auto";

        if (configLang !== "auto")
            return configLang;

        return Qt.locale().name;
    }

    TranslationScanner {
        id: scanLanguagesProcess
        translationsDir: root.translationsDir
        onLanguagesScanned: (languages) => {
            root.availableLanguages = [...languages];
        }
    }

    TranslationScanner {
        id: scanGeneratedLanguagesProcess
        translationsDir: root.generatedTranslationsDir
        onLanguagesScanned: (languages) => {
            root.availableGeneratedLanguages = [...languages];
        }
    }

    onLanguageCodeChanged: {
        if (root.languageCode === "")
            return;
        print("[Translation] Language changed to", root.languageCode);
        translationFileView.reread(root.languageCode);
        generatedTranslationFileView.reread(root.languageCode);
    }

    TranslationReader {
        id: translationFileView
        translationsDir: root.translationsDir
        onContentLoaded: (data) => {
            root.translations = data;
            root.isLoading = false;
        }
    }

    TranslationReader {
        id: generatedTranslationFileView
        translationsDir: root.generatedTranslationsDir
        onContentLoaded: (data) => {
            root.generatedTranslations = data;
            root.isLoading = false;
        }
    }

    function tr(text) {
        // Special cases
        if (!text) return "";
        var key = text.toString();
        if (root.isLoading || (!root?.translations?.hasOwnProperty(key) && !root?.generatedTranslations?.hasOwnProperty(key) && !root?.pluginTranslations?.hasOwnProperty(key)))
            return key;

        // Normal cases. A plugin comes last on purpose: a word the shell already
        // has ("Off", "Default") keeps the shell's wording everywhere, and only
        // what is genuinely the plugin's own comes from the plugin.
        // Subscripted through the optional operator, like the guard above it. The
        // guard used to be the proof that one of the two shell maps held the key
        // and was therefore a map at all; a third source can satisfy it on its
        // own, and a map that has not been read yet is null rather than empty.
        var translation = root.translations?.[key] || root.generatedTranslations?.[key] || root.pluginTranslations?.[key] || key;
        // print(key, "-> [", root.translations[key], root.generatedTranslations[key], key, "] ->", translation);
        if (translation.endsWith(root.translationKeepSuffix)) {
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        }
        return translation;
    }

    /**
     * One plugin's file for the current language.
     *
     * The path is bound rather than assigned, unlike the two readers above: those
     * carry a documented history of a binding being overwritten, which does not
     * apply to a component created per directory and never assigned to.
     */
    component PluginTranslation: QtObject {
        id: pluginTranslation
        required property string directory

        readonly property FileView file: FileView {
            // Most plugins ship no translations at all, and most of those that do
            // will not have this language. Absence is the normal case here, so it
            // is handled below rather than announced.
            printErrors: false
            path: root.languageCode.length > 0
                ? `${root.pluginTranslationsRoot}/${pluginTranslation.directory}/translations/${root.languageCode}.json`
                : ""
            onLoaded: {
                try {
                    root.takePluginTranslations(pluginTranslation.directory, JSON.parse(text()));
                } catch (error) {
                    console.log(`[Translation] ${pluginTranslation.directory}: translations are not JSON`);
                }
            }
            // A plugin that ships no translation for this language is the normal
            // case, not a fault: it falls back to the English in its own source.
            onLoadFailed: root.takePluginTranslations(pluginTranslation.directory, {})
        }
    }

    readonly property string pluginTranslationsRoot: FileUtils.trimFileProtocol(Quickshell.shellPath("plugins"))

    property Instantiator pluginReaders: Instantiator {
        model: Plugins.directories
        delegate: PluginTranslation {
            required property string modelData
            directory: modelData
        }
    }

    component TranslationScanner: Process {
        id: translationScanner
        required property string translationsDir
        signal languagesScanned(var languages)

        command: ["find", translationScanner.translationsDir, "-name", "*.json", "-exec", "basename", "{}", ".json", ";"]
        running: true

        stdout: StdioCollector {
            id: languagesCollector
            onStreamFinished: {
                const output = languagesCollector.text;
                const files = output.trim().split('\n').map(f => f.trim());
                translationScanner.languagesScanned(files);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                translationScanner.languagesScanned(["en_US"]);
            }
        }
    }

    component TranslationReader: FileView {
        id: translationReader
        required property string translationsDir
        signal contentLoaded(var data)

        // The code is passed in rather than mirrored on a property here: the mirror
        // was bound to the singleton and then assigned over on every switch, which
        // broke the binding on the first one and left it decorative. Clearing the
        // path is already what forces the file to be read again, so the reload()
        // that used to follow only ever read it a second time.
        function reread(languageCode) {
            translationReader.path = "";
            translationReader.path = `${translationReader.translationsDir}/${languageCode}.json`;
        }
        path: ""

        onLoaded: {
            var textContent = "";
            try {
                textContent = text();
                var jsonData = JSON.parse(textContent);
                translationReader.contentLoaded(jsonData);
            } catch (e) {
                console.log("[Translation] Failed to load translations:", e);
                translationReader.contentLoaded({});
            }
        }
        onLoadFailed: error => {
            translationReader.contentLoaded({});
        }
    }
}
