"""Minimising: a window parked on a special workspace and brought back."""


def test_application_asks_to_be_minimised_and_comes_back_where_it_stood(desk):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    before = window.rect

    window.command("minimize")
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")

    desk.shell.call("minimize", "toggle", window.address)
    client = window.wait(lambda c: c["workspace"]["id"] == workspace, "brought back")
    assert (*client["at"], *client["size"]) == before


def test_super_down_from_where_it_stands_minimises(desk):
    window = desk.wayland()
    workspace = window.client()["workspace"]["id"]
    desk.shell.call("placement", "step", "down")
    window.wait(lambda c: c["workspace"]["name"] == f"special:min-{workspace}", "minimised")
