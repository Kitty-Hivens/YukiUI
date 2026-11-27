"""An application started from the shell runs in a systemd scope of its own.

Started straight from the shell, it ran in the shell's own scope, where the
memory kept for the shell was shared with it and taking the shell's scope down
took the application along. The application here is a desktop entry of the
test's own, which writes down the cgroup it finds itself in.
"""

import os

from bench.bench import SHELL, wait_until
from bench.shell import Shell

PROBE = SHELL / "benchAppScopeProbe.qml"
SOURCE = """import QtQuick
import Quickshell
import Quickshell.Io
import qs.core.services

// Written by tests/core/test_app_scopes.py for a test run, and removed after it.
ShellRoot {
    Component.onCompleted: AppLaunch.load()
    IpcHandler {
        target: "scopeProbe"
        function ready(): bool {
            return AppLaunch.scoped && DesktopEntries.byId("bench-scoped") !== null;
        }
        function launch(): void {
            AppLaunch.run(DesktopEntries.byId("bench-scoped"));
        }
    }
}
"""


def test_an_application_gets_a_scope_of_its_own(bench, tmp_path):
    seen = tmp_path / "cgroup"
    apps = tmp_path / "share/applications"
    apps.mkdir(parents=True)
    (apps / "bench-scoped.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Bench scoped\n"
        f"Exec=sh -c \"cat /proc/self/cgroup > {seen}\"\n")
    dirs = f"{tmp_path / 'share'}:{os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')}"
    shell = Shell(bench, probe=PROBE, source=SOURCE, ready=("scopeProbe", "ready"), env={"XDG_DATA_DIRS": dirs})
    try:
        shell.start()
        wait_until(lambda: shell.call("scopeProbe", "ready") == "true", timeout=10, what="a user manager to put scopes in")
        shell.call("scopeProbe", "launch")
        wait_until(lambda: seen.exists() and seen.read_text().strip(), timeout=10, what="the application to say where it runs")
        cgroup = seen.read_text().strip().split("::")[-1]
        own = open(f"/proc/{shell.process.pid}/cgroup").read().strip().split("::")[-1]
        assert "/app-graphical.slice/app-yuki-bench_scoped-" in cgroup, cgroup
        assert cgroup != own
    finally:
        shell.stop()
        shell.remove_probe()
