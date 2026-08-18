pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.waffle.widgets.cards

DelegateChooser {
    id: root

    DelegateChoice {
        roleValue: "weather"
        WeatherCard {}
    }
    DelegateChoice {
        roleValue: "calendar"
        CalendarCard {}
    }
    DelegateChoice {
        roleValue: "todo"
        TodoCard {}
    }
    DelegateChoice {
        roleValue: "media"
        MediaCard {}
    }
    DelegateChoice {
        roleValue: "resources"
        ResourcesCard {}
    }
}
