"""Text written by others, shown without being read as markup.

Qt reads markup into a Text that looks like it, an <img> included, which the
shell then fetched. A server on the loopback stands in for the place such a
picture points to, and nothing may ask it for anything.
"""

import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from bench.bench import SHELL
from bench.shell import Shell

PROBE = SHELL / "benchMarkupProbe.qml"


class Listener:
    """A web server that only writes down what it is asked for."""

    def __init__(self):
        self.requests = []
        listener = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                listener.requests.append(self.path)
                self.send_response(404)
                self.end_headers()

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def url(self, name: str) -> str:
        return f"http://127.0.0.1:{self.port}/{name}"

    def close(self):
        self.server.shutdown()


@pytest.fixture
def listener():
    listener = Listener()
    yield listener
    listener.close()


def probe(bench, body: str) -> Shell:
    source = f"""import QtQuick
import Quickshell
import Quickshell.Io
import qs.experimental.looks

// Written by tests/experimental/test_markup.py for a test run, and removed after it.
ShellRoot {{
    FloatingWindow {{
        implicitWidth: 400
        implicitHeight: 200
{body}
    }}
    IpcHandler {{
        target: "markupProbe"
        function ready(): string {{
            return "yes";
        }}
    }}
}}
"""
    return Shell(bench, probe=PROBE, source=source, ready=("markupProbe", "ready"))


def test_text_by_others_fetches_nothing(bench, listener):
    # As a window title or a polkit message would carry it.
    shell = probe(bench, f'        ExText {{ text: "Title <img src=\\"{listener.url("title.png")}\\">" }}')
    try:
        shell.start()
        time.sleep(1.5)
    finally:
        shell.stop()
        shell.remove_probe()
    assert listener.requests == []
