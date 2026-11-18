pragma Singleton

import qs.core
import qs.core.functions
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    // Both answers below are worked out by fuzzy-searching every installed entry
    // when the cheap guesses miss, and both are asked from bindings that re-run
    // whenever a window opens, closes or is focused. The answers only change when
    // the set of installed applications does.
    property var iconGuessCache: ({})
    property var entryLookupCache: ({})
    property var heuristicLookupCache: ({})
    onListChanged: {
        root.iconGuessCache = ({});
        root.entryLookupCache = ({});
        root.heuristicLookupCache = ({});
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    // Central icon-source helpers used by the widgets. NOTE: the intermittent "icon dropped
    // after hot-reload" is a Quickshell/Qt issue, not something these can fix -- the image://icon/
    // provider calls QIcon::fromTheme(), whose QIconLoader caches a null for names queried during
    // the brief post-reload window before the theme is warm, and keeps it until a full restart.
    function iconPathCached(name) {
        return Quickshell.iconPath(name, "image-missing");
    }

    /**
     * The icon to show for a window class, best first: the theme's icon for a
     * desktop entry of that name, the icon Steam installed for the game a
     * window belongs to, the icon a window gave itself, a name from the theme
     * or a picture, and then the guesses. A window's own icon comes after an
     * entry's, so applications with one look alike in the theme, and before
     * the guesses, which named Minecraft after an icon no theme here has.
     */
    function iconFor(appClass) {
        const icon = root.iconNameFor(appClass);
        return icon.startsWith("file://") ? icon : root.iconPathCached(icon);
    }

    /**
     * The same choice as `iconFor`, given as the name of an icon in the theme,
     * or for a picture a window gave itself as its file's url: for widgets that
     * take an icon by name and a picture by its url, Kirigami's among them.
     */
    function iconNameFor(appClass) {
        const entry = DesktopEntries.byId(appClass);
        if (entry)
            return entry.icon;
        const steam = WindowIcons.steamAppOf(appClass);
        if (steam && root.iconExists(`steam_icon_${steam}`))
            return `steam_icon_${steam}`;
        const own = WindowIcons.nameOf(appClass);
        if (own && root.iconExists(own))
            return own;
        const picture = WindowIcons.pictureOf(appClass);
        if (picture)
            return picture;
        return root.guessIcon(appClass);
    }

    /**
     * The desktop entry a window class belongs to, guessed the same way its icon is.
     *
     * Quickshell's own lookup goes by file name and by the class an entry declares it
     * starts windows under, and a great many entries declare neither -- GitHub Desktop
     * puts its windows under a class that matches its readable name and nothing else,
     * so asking for its entry came back with nothing while its icon was found without
     * trouble. That left the taskbar showing an application it could not launch.
     */
    function entryFor(appClass) {
        if (!appClass || appClass.length == 0) return null;
        if (!(appClass in root.entryLookupCache))
            root.entryLookupCache[appClass] = root.lookUpEntry(appClass);
        const named = root.entryLookupCache[appClass];
        if (named) return named;

        // A game Steam started, whose entry Steam names after the game. Asked
        // after the cache, since which game a window is comes a moment later.
        const steam = WindowIcons.steamAppOf(appClass);
        const fromSteam = steam ? root.steamEntry(steam) : null;
        if (fromSteam) return fromSteam;

        if (!(appClass in root.heuristicLookupCache))
            root.heuristicLookupCache[appClass] = DesktopEntries.heuristicLookup(appClass);
        return root.heuristicLookupCache[appClass];
    }

    function lookUpEntry(appClass) {
        const guesses = [
            appClass,
            root.getKebabNormalizedAppName(appClass),
            root.getUndescoreToKebabAppName(appClass),
            root.getReverseDomainNameAppName(appClass)
        ];
        for (const guess of guesses) {
            const entry = DesktopEntries.byId(guess);
            if (entry) return entry;
        }
        return null;
    }

    /** The desktop entry Steam installed for a game: its icon is named for the game's id, and it starts the game by it. */
    function steamEntry(appId) {
        return root.list.find(entry => entry.icon === `steam_icon_${appId}` || (entry.execString ?? "").includes(`rungameid/${appId}`)) ?? null;
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";
        if (str in root.iconGuessCache) return root.iconGuessCache[str];

        const icon = root.workOutIcon(str);
        root.iconGuessCache[str] = icon;
        return icon;
    }

    function workOutIcon(str) {
        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions, and the regex ones, each only for an icon the
        // theme has: Minecraft was named after one no theme here carries, and
        // showed as missing rather than as anything found further on.
        if (substitutions[str] && iconExists(substitutions[str])) return substitutions[str];
        if (substitutions[str.toLowerCase()] && iconExists(substitutions[str.toLowerCase()])) return substitutions[str.toLowerCase()];

        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str && iconExists(replacedName)) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
