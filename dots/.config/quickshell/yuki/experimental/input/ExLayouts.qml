import QtQuick
import Quickshell

import qs.core.services

/**
 * The keyboard layouts as the dock names them: by the language each one is
 * for, rather than by its xkb code.
 *
 * Most layouts are named after their language already. The few that are
 * named after a country are listed here, and anything else is shown as it is.
 */
QtObject {
    id: root

    readonly property var languageOf: ({
        "us": "en",
        "gb": "en",
        "ua": "uk",
        "by": "be",
        "kz": "kk",
        "cz": "cs",
        "dk": "da",
        "ee": "et",
        "gr": "el",
        "se": "sv",
        "jp": "ja",
        "kr": "ko",
        "cn": "zh",
        "il": "he",
        "ir": "fa",
        "br": "pt",
        "latam": "es"
    })

    readonly property var codes: HyprlandXkb.layoutCodes
    readonly property int current: Math.max(0, root.codes.indexOf(HyprlandXkb.currentLayoutCode))

    function language(code: string): string {
        const base = (code || "").split(/[(:-]/)[0];
        return root.languageOf[base] ?? base;
    }

    /** Two letters for the dock, the language's. */
    function short(code: string): string {
        return root.language(code).slice(0, 2).toUpperCase();
    }

    /** The language's own name for itself, for the list. */
    function name(code: string): string {
        const native = Qt.locale(root.language(code)).nativeLanguageName;
        if (!native || native.length === 0)
            return code;
        return native.charAt(0).toUpperCase() + native.slice(1);
    }

    function select(index: int) {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(index)]);
    }
}
