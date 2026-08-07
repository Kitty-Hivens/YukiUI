pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.waffle.widgets.cards

// One card by name. The board picks its cards through a delegate chooser, which
// only works as a delegate; this is the same choice made anywhere else.
Loader {
    id: root

    required property string cardId
    /// Shown as an offer rather than as part of the board.
    property bool sample: false

    sourceComponent: {
        switch (root.cardId) {
        case "weather":
            return weatherCard;
        case "calendar":
            return calendarCard;
        case "todo":
            return todoCard;
        case "media":
            return mediaCard;
        case "resources":
            return resourcesCard;
        }
        return null;
    }

    Component {
        id: weatherCard
        WeatherCard {
            sample: root.sample
        }
    }
    Component {
        id: calendarCard
        CalendarCard {
            sample: root.sample
        }
    }
    Component {
        id: todoCard
        TodoCard {
            sample: root.sample
        }
    }
    Component {
        id: mediaCard
        MediaCard {
            sample: root.sample
        }
    }
    Component {
        id: resourcesCard
        ResourcesCard {
            sample: root.sample
        }
    }
}
