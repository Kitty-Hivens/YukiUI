pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * What the board is doing and what can be done to it.
 *
 * The cards are laid out by a repeater over a list in the configuration, so
 * arranging them is arranging that list. Editing is a state of the board rather
 * than of any one card, which is why it lives here and not in the panel.
 */
Singleton {
    id: root

    property bool editing: false

    /// A wider board fits another column of cards. Kept across sessions.
    property bool wide: Persistent.states.widgets.wide
    onWideChanged: Persistent.states.widgets.wide = root.wide
    readonly property int columns: root.wide ? 3 : 2

    /// Everything that can be put on the board, in the order it is offered.
    readonly property list<string> knownCards: ["weather", "calendar", "todo"]

    readonly property list<string> pinnedCards: Config.options?.waffles.widgets.cards ?? []
    readonly property list<string> unpinnedCards: root.knownCards.filter(card => root.pinnedCards.indexOf(card) === -1)

    function nameOf(cardId) {
        switch (cardId) {
        case "weather":
            return Translation.tr("Weather");
        case "calendar":
            return Translation.tr("Calendar");
        case "todo":
            return Translation.tr("To do");
        }
        return cardId;
    }

    function iconOf(cardId) {
        switch (cardId) {
        case "weather":
            return "weather-sunny";
        case "calendar":
            return "calendar-add";
        case "todo":
            return "checkmark";
        }
        return "apps";
    }

    /// How many columns a card takes. Two is as far as it goes: the board is two
    /// columns at its narrowest, and a third size would collapse onto one of these.
    readonly property list<string> wideCards: Config.options?.waffles.widgets.wideCards ?? []

    function spanOf(cardId) {
        return root.wideCards.indexOf(cardId) !== -1 ? 2 : 1;
    }

    function toggleSpan(cardId) {
        if (root.spanOf(cardId) === 2)
            Config.options.waffles.widgets.wideCards = root.wideCards.filter(card => card !== cardId);
        else
            Config.options.waffles.widgets.wideCards = root.wideCards.concat([cardId]);
    }

    /// Where the cards sit. Kept as "id:column,row" so a card holds its place
    /// rather than being packed against its neighbours -- the grid a card is put
    /// on is the grid it stays on, gaps and all.
    readonly property list<string> placements: Config.options?.waffles.widgets.placements ?? []

    function placementOf(cardId) {
        for (const entry of root.placements) {
            const parts = entry.split(":");
            if (parts[0] !== cardId || parts.length < 2)
                continue;
            const at = parts[1].split(",");
            return ({
                    column: parseInt(at[0]),
                    row: parseInt(at[1])
                });
        }
        return null;
    }

    function setPlacement(cardId, column, row) {
        const others = root.placements.filter(entry => entry.split(":")[0] !== cardId);
        Config.options.waffles.widgets.placements = others.concat([`${cardId}:${column},${row}`]);
    }

    function setPlacements(entries) {
        Config.options.waffles.widgets.placements = entries;
    }

    function forgetPlacement(cardId) {
        Config.options.waffles.widgets.placements = root.placements.filter(entry => entry.split(":")[0] !== cardId);
    }

    function addCard(cardId) {
        if (root.pinnedCards.indexOf(cardId) !== -1)
            return;
        Config.options.waffles.widgets.cards = root.pinnedCards.concat([cardId]);
    }

    function removeCard(cardId) {
        Config.options.waffles.widgets.cards = root.pinnedCards.filter(card => card !== cardId);
        root.forgetPlacement(cardId);
    }

    /// Puts a card where another one is, which is what dropping it there means.
    function moveCardTo(cardId, index) {
        const cards = root.pinnedCards.slice();
        const from = cards.indexOf(cardId);
        if (from === -1 || index < 0 || index >= cards.length || from === index)
            return;
        cards.splice(index, 0, cards.splice(from, 1)[0]);
        Config.options.waffles.widgets.cards = cards;
    }

    /// Moves a card by one place, for the keyboard.
    function moveCard(cardId, delta) {
        const cards = root.pinnedCards.slice();
        const from = cards.indexOf(cardId);
        const to = from + delta;
        if (from === -1 || to < 0 || to >= cards.length)
            return;
        cards.splice(to, 0, cards.splice(from, 1)[0]);
        Config.options.waffles.widgets.cards = cards;
    }

    function canMove(cardId, delta) {
        const index = root.pinnedCards.indexOf(cardId);
        const target = index + delta;
        return index !== -1 && target >= 0 && target < root.pinnedCards.length;
    }
}
