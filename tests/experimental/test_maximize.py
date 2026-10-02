"""Maximising, as the experimental environment does it.

The shell maximises a floating window by giving it the work area and telling
it so, and puts it back where it stood. Hyprland's own maximise, a kind of
fullscreen, is suppressed by the environment's rules.
"""


def area(desk):
    return desk.bench.work_area


def is_maximized(desk, client) -> bool:
    x, y, w, h = area(desk)
    return (client["fullscreenClient"] == 1 and client["fullscreen"] == 0 and "maximized" in client["tags"]
            and tuple(client["at"]) == (x, y) and tuple(client["size"]) == (w, h))


def believes(state) -> set:
    """What the window was told of its placement, of the states that matter here."""
    return {name for name in state["toplevel"] if name == "maximized" or name.endswith("tiled")}


def ordinary(state) -> bool:
    """Told it is tiled, so it draws no shadow of its own, and not maximised."""
    return "tiled" in believes(state) and "maximized" not in believes(state)


def told_maximized(state) -> bool:
    return "maximized" in believes(state)


def test_new_window_is_not_told_it_is_maximized(desk):
    # Hyprland tells every Wayland window it is maximised as it maps.
    window = desk.wayland()
    window.wait_state(ordinary, "it is an ordinary window")


def test_maximize_and_restore_wayland(desk):
    window = desk.wayland()
    before = window.rect

    desk.toggle_maximized(window)
    window.wait(lambda c: is_maximized(desk, c), "maximised")
    window.wait_state(told_maximized, "it is maximised")

    desk.toggle_maximized(window)
    client = window.wait(lambda c: c["fullscreenClient"] == 0 and not c["tags"], "put back")
    assert (*client["at"], *client["size"]) == before
    window.wait_state(ordinary, "it is an ordinary window again")


def test_application_asks_to_be_maximized(desk):
    window = desk.wayland()
    before = window.rect

    window.command("maximize")
    window.wait(lambda c: is_maximized(desk, c), "maximised at its own request")

    window.command("unmaximize")
    client = window.wait(lambda c: c["fullscreenClient"] == 0 and not c["tags"], "put back at its own request")
    assert (*client["at"], *client["size"]) == before


def test_super_arrows_follow_the_table(desk):
    window = desk.wayland()
    x, y, w, h = area(desk)
    half = round(w / 2)
    steps = [
        ("left", (x, y, half, h)),
        ("up", (x, y, half, round(h / 2))),
        ("right", (x + half, y, w - half, round(h / 2))),
        ("down", (x + half, y, w - half, h)),
        ("up", (x + half, y, w - half, round(h / 2))),
        ("up", (x, y, w, h)),
    ]
    for direction, rect in steps:
        desk.shell.call("placement", "step", direction)
        window.wait(lambda c, rect=rect: (*c["at"], *c["size"]) == rect, f"after {direction} at {rect}")


def test_window_opening_as_large_as_the_work_area_is_maximized_x11(desk):
    x, y, w, h = area(desk)
    window = desk.x11(x=x, y=y, width=w, height=h)
    window.wait(lambda c: is_maximized(desk, c), "maximised as it opened")
    window.wait_state(lambda s: "_NET_WM_STATE_MAXIMIZED_VERT" in s["net_wm_state"], "it is maximised")


def test_window_opening_as_large_as_the_work_area_is_maximized_wayland(desk):
    _, _, w, h = area(desk)
    window = desk.wayland(width=w, height=h)
    window.wait(lambda c: is_maximized(desk, c), "maximised as it opened")


def test_ordinary_window_is_not_maximized_as_it_opens(desk):
    window = desk.x11(width=900, height=600)
    window.wait(lambda c: c["fullscreenClient"] == 0 and not c["tags"], "an ordinary window", timeout=3)
    assert window.client()["size"] == [900, 600]


def test_x11_maximize_button_works_both_ways(desk):
    window = desk.x11(width=800, height=500)
    before = window.rect
    window.command("netstate toggle maximized")
    window.wait(lambda c: is_maximized(desk, c), "maximised by its own button")
    window.wait_state(lambda s: "_NET_WM_STATE_MAXIMIZED_VERT" in s["net_wm_state"], "it is maximised")
    window.command("netstate toggle maximized")
    client = window.wait(lambda c: c["fullscreenClient"] == 0 and not c["tags"], "put back by its own button")
    assert (*client["at"], *client["size"]) == before
    window.wait_state(lambda s: not s["net_wm_state"] or s["net_wm_state"] == ["_NET_WM_STATE_FOCUSED"],
                      "it is not maximised")


def test_placement_outlives_a_shell_restart(desk):
    maximized = desk.wayland()
    snapped = desk.wayland()
    desk.place(maximized, "maximized")
    desk.place(snapped, "left")
    maximized.wait(lambda c: is_maximized(desk, c), "maximised")
    snapped.wait(lambda c: "snapped" in c["tags"], "snapped")

    desk.shell.restart()

    placed = desk.placed()
    assert placed[maximized.address]["zone"] == "maximized"
    assert placed[snapped.address]["zone"] == "left"
    assert "maximized" in maximized.client()["tags"]
    assert "snapped" in snapped.client()["tags"]


def test_placement_outlives_a_config_reload(desk):
    window = desk.wayland()
    desk.place(window, "maximized")
    window.wait(lambda c: is_maximized(desk, c), "maximised")
    desk.bench.reload()
    # The compositor's lua starts afresh, and the shell tells it again.
    from bench.bench import wait_until
    wait_until(lambda: desk.bench.lua_value(f'YUKI_PLACED["{window.address}"] ~= nil') == "true",
               what="the compositor to know where the window stood again")
    assert "maximized" in window.client()["tags"]
