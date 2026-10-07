"""The clipboard helper: several forms of one thing on the clipboard at once.

Run against the nested compositor's own clipboard, so the person's is never
touched.
"""

import subprocess
import time

from bench.bench import wait_until


def paste(bench, *args) -> subprocess.CompletedProcess:
    return subprocess.run(["wl-paste", *args], env=bench.environment(), capture_output=True)


def test_every_form_is_offered_and_served(bench, tmp_path):
    picture = tmp_path / "shot.png"
    picture.write_bytes(b"\\x89PNG fake" * 200000)
    uri = f"file://{picture}"
    result = subprocess.run([str(bench.clip_tool), "-f", "image/png", str(picture), "-t", "text/uri-list", f"{uri}\r\n",
                             "-t", "text/plain;charset=utf-8", str(picture)], env=bench.environment(), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    # Read before anything else, so the file can go at once.
    picture.unlink()
    types = paste(bench, "--list-types").stdout.decode().split()
    assert types == ["image/png", "text/uri-list", "text/plain;charset=utf-8"]
    assert paste(bench, "--type", "image/png").stdout == b"\\x89PNG fake" * 200000
    assert paste(bench, "--no-newline", "--type", "text/plain;charset=utf-8").stdout.decode() == str(picture)


def test_it_leaves_once_something_else_is_copied(bench):
    subprocess.run([str(bench.clip_tool), "-t", "text/plain", "first"], env=bench.environment(), check=True)
    serving = lambda: subprocess.run(["pgrep", "-f", f"^{bench.clip_tool} -t text/plain first$"], capture_output=True).returncode == 0
    assert serving()
    subprocess.run(["wl-copy", "second"], env=bench.environment(), check=True)
    wait_until(lambda: not serving(), what="the helper to leave")
    assert paste(bench, "--no-newline").stdout == b"second"
