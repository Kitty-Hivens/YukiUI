"""A plugin's settings page is offered to the family it is drawn for.

A page is drawn with a family's own kit, and the one plugin page there was
imported ii's settings widgets, so under any other desktop it could only load
another desktop's look or fail. A manifest names a page per family, or one for
all of them written against the shared widgets.
"""

import json
import shutil

import pytest

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchPluginPagesProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services

// Written by tests/core/test_plugin_pages.py for a test run, and removed after it.
ShellRoot {
    IpcHandler {
        target: "pagesProbe"
        function pages(family: string): string {
            if (!Config.ready)
                return "";
            return JSON.stringify(Plugins.pagesFor(family).map(page => [page.key, page.url.split("/").pop()]));
        }
    }
}
"""


def plugin(root, pid, page):
    directory = root / pid
    directory.mkdir(parents=True)
    (directory / "Plugin.qml").write_text("import QtQuick\nQtObject {}\n")
    (directory / "manifest.json").write_text(json.dumps({
        "id": pid, "name": pid, "apiVersion": 1, "entry": "Plugin.qml",
        "settingsPage": dict({"key": pid, "name": pid}, **page),
    }))


@pytest.fixture
def plugins(bench):
    root = bench.config_home / "yuki/plugins"
    shutil.rmtree(root, ignore_errors=True)
    plugin(root, "benchOwn", {"entries": {"ii": "IiPage.qml"}})
    plugin(root, "benchShared", {"entry": "SharedPage.qml", "entries": {"blueberry": "BlueberryPage.qml"}})
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("pagesProbe", "pages", "ii"))
    try:
        shell.start()
        yield shell
    finally:
        shell.stop()
        shell.remove_probe()
        shutil.rmtree(root, ignore_errors=True)


def pages(shell, family):
    def read():
        text = shell.call("pagesProbe", "pages", family)
        found = json.loads(text) if text else []
        return found if any(key.startswith("bench") for key, _ in found) else None
    return {key: file for key, file in wait_until(read, what=f"the pages for {family}") if key.startswith("bench")}


def test_each_family_is_offered_the_pages_drawn_for_it(plugins):
    assert pages(plugins, "ii") == {"benchOwn": "IiPage.qml", "benchShared": "SharedPage.qml"}
    assert pages(plugins, "blueberry") == {"benchShared": "BlueberryPage.qml"}
    assert pages(plugins, "waffle") == {"benchShared": "SharedPage.qml"}


PAGE_PROBE = SHELL / "benchPortalsPageProbe.qml"
PAGE_SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.ii.systemSettings

// Written by tests/core/test_plugin_pages.py for a test run, and removed after it.
ShellRoot {
    id: probe
    property var page: null
    property string error: ""
    Component.onCompleted: {
        // By the url the settings load it from, which Plugins hands out.
        const component = Qt.createComponent(`file://${Plugins.systemRoot}/portals/SettingsPage.qml`);
        if (component.status !== Component.Ready) {
            probe.error = component.errorString();
            return;
        }
        probe.page = component.createObject(null);
    }
    IpcHandler {
        target: "portalsPageProbe"
        function state(): string {
            const model = probe.page ? Array.from(probe.page.resources).find(child => child.interfaces !== undefined) ?? null : null;
            return JSON.stringify({ error: probe.error, built: probe.page !== null, read: model?.report !== null && model?.report !== undefined });
        }
    }
}
"""


def test_the_portals_page_of_ii_builds_and_reads_the_portals(bench):
    shell = Shell(bench, probe=PAGE_PROBE, source=PAGE_SOURCE, ready=("portalsPageProbe", "state"))
    try:
        shell.start()
        def settled():
            state = json.loads(shell.call("portalsPageProbe", "state"))
            return state if state["read"] or state["error"] else None
        state = wait_until(settled, timeout=10, what="the page to read the portals")
    finally:
        shell.stop()
        shell.remove_probe()
    assert state == {"error": "", "built": True, "read": True}
