pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var translations: ({})
    property var generatedTranslations: ({})
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
        if (root.isLoading || (!root?.translations?.hasOwnProperty(key) && !root?.generatedTranslations?.hasOwnProperty(key)))
            return key;
        
        // Normal cases
        var translation = root.translations[key] || root.generatedTranslations[key] || key;
        // print(key, "-> [", root.translations[key], root.generatedTranslations[key], key, "] ->", translation);
        if (translation.endsWith(root.translationKeepSuffix)) {
            translation = translation.substring(0, translation.length - root.translationKeepSuffix.length).trim();
        }
        return translation;
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
