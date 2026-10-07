"""The capture-report plugin: which programs take the screen from the compositor.

The compositor says the screen is being taken, and what of it, but not by whom.
The plugin names every program taking it whenever that changes, and again when
asked. A screen recorder on the bench stands in for any such program.
"""

import json
import signal
import subprocess
import time

from bench.bench import OUTPUT, wait_until


def capturers(bench, since):
    return [json.loads(event.data) for event in bench.events.since(since, "capturers")]


def test_a_recorder_is_named_while_it_records(bench, tmp_path):
    mark = bench.events.mark()
    recorder = subprocess.Popen(["wf-recorder", "-o", OUTPUT, "-f", str(tmp_path / "taken.mp4"), "-y"],
                                env=bench.environment(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        def named():
            lists = capturers(bench, mark)
            return next((entry for entries in lists for entry in entries if entry["pid"] == recorder.pid), None)
        entry = wait_until(named, timeout=5, what="the recorder to be named")
        assert entry["name"] == "wf-recorder"
        assert entry["type"] in ("monitor", "region")

        # Asked for again, as a shell that has just started does.
        asked = bench.events.mark()
        bench.eval("hl.plugin.capture_report.announce()")
        wait_until(lambda: any(e["pid"] == recorder.pid for entries in capturers(bench, asked) for e in entries),
                   what="the list to be told again")
    finally:
        recorder.send_signal(signal.SIGINT)
        try:
            recorder.wait(timeout=3)
        except subprocess.TimeoutExpired:
            recorder.kill()
            recorder.wait(timeout=5)

    stopped = bench.events.mark()
    time.sleep(0.2)
    bench.eval("hl.plugin.capture_report.announce()")
    wait_until(lambda: any(entries == [] or all(e["pid"] != recorder.pid for e in entries) for entries in capturers(bench, stopped)),
               timeout=5, what="the recorder to be gone from the list")
