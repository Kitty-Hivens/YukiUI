"""The portal's file chooser and the filter an application starts on.

An application names the filter to start on in current_filter, and one that
saves in the format its filter names reads the filter picked back from the
reply. Neither way was passed on.
"""

import sys

from bench.bench import SHELL

sys.path.insert(0, str(SHELL / "scripts/portal"))

import filechooser  # noqa: E402

IMAGES = ("Images", [(0, "*.png"), (1, "image/jpeg")])
TEXT = ("Text", [(0, "*.txt")])


def test_the_dialog_starts_on_the_filter_asked_for():
    request = filechooser._build_request("SaveFile", "Save", {"filters": [IMAGES, TEXT], "current_filter": TEXT})
    assert [entry["name"] for entry in request["filters"]] == ["Images", "Text"]
    assert request["currentFilter"] == 1


def test_a_filter_asked_for_without_a_list_is_the_one_filter():
    request = filechooser._build_request("OpenFile", "Open", {"current_filter": IMAGES})
    assert request["filters"] == [{"name": "Images", "patterns": ["*.png"], "mimes": ["image/jpeg"]}]
    assert request["currentFilter"] == 0


def test_a_filter_asked_for_that_is_not_listed_starts_on_the_first():
    request = filechooser._build_request("OpenFile", "Open", {"filters": [IMAGES, TEXT], "current_filter": ("Other", [])})
    assert request["currentFilter"] == 0


def test_the_filter_picked_goes_back_to_the_application():
    options = {"filters": [IMAGES, TEXT]}
    chosen = filechooser._chosen_filter(options, 1)
    results = filechooser._results(["file:///tmp/a.txt"], chosen)
    assert results["current_filter"].unpack() == ("Text", [(0, "*.txt")])


def test_no_filter_goes_back_for_a_place_not_in_the_list():
    options = {"filters": [IMAGES]}
    assert filechooser._chosen_filter(options, 3) is None
    assert filechooser._chosen_filter(options, None) is None
    assert "current_filter" not in filechooser._results(["file:///tmp/a.png"], None)
