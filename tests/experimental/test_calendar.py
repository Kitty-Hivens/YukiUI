"""The calendar under the notification center, turned faster than it scrolls."""

import json

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchCalendarProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.experimental.notificationCenter

// Written by tests/experimental/test_calendar.py for a test run, and removed after it.
ShellRoot {
    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 360
        ExCalendar {
            id: calendar
        }
    }

    IpcHandler {
        target: "calendarProbe"
        // Clicks on an arrow, one right after another, as a double click.
        function turn(step: int, times: int): void {
            for (let i = 0; i < times; i++)
                calendar.turn(step);
        }
        function backToToday(): void {
            calendar.backToToday();
        }
        function state(): string {
            return JSON.stringify({ year: calendar.year, month: calendar.month,
                                    today: [calendar.today.getFullYear(), calendar.today.getMonth()] });
        }
    }
}
"""


@pytest.fixture
def calendar(bench):
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("calendarProbe", "state"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()


def state(shell) -> dict:
    return json.loads(shell.call("calendarProbe", "state"))


def months_from_today(shell) -> int:
    now = state(shell)
    year, month = now["today"]
    return (now["year"] - year) * 12 + now["month"] - month


def test_two_quick_clicks_turn_two_months(calendar):
    calendar.call("calendarProbe", "turn", "1", "2")
    wait_until(lambda: months_from_today(calendar) == 2, timeout=3, what="two months on")


def test_quick_clicks_both_ways_cancel_out(calendar):
    calendar.call("calendarProbe", "turn", "-1", "3")
    wait_until(lambda: months_from_today(calendar) == -3, timeout=3, what="three months back")
    calendar.call("calendarProbe", "turn", "1", "1")
    calendar.call("calendarProbe", "backToToday")
    wait_until(lambda: months_from_today(calendar) == 0, timeout=3, what="back to this month")
