"""What an X11 application asks for through _NET_WM_STATE and WM_CHANGE_STATE.

Under XWayland Hyprland keeps a request on the window until the application
asks for the opposite, and every later change of state ran the minimize
plugin's listener with the old request still there. A window that had
minimised itself once, Steam for one, was minimised again each time it went
in or out of fullscreen.
"""

import time


def minimize_requests(desk, window, mark):
    return [e for e in desk.bench.events.since(mark, "minimized") if f"0x{e.data.split(',')[0]}" == window.address]


def test_minimising_once_does_not_come_back_with_fullscreen(desk):
    window = desk.x11()
    mark = desk.bench.events.mark()
    window.command("iconify")
    window.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised")
    desk.shell.call("minimize", "toggle", window.address)
    window.wait(lambda c: not c["workspace"]["name"].startswith("special:"), "brought back")

    window.command("netstate add fullscreen")
    window.wait(lambda c: c["fullscreen"] != 0, "fullscreen")
    window.command("netstate remove fullscreen")
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
    time.sleep(0.5)

    assert len(minimize_requests(desk, window, mark)) == 1
    assert not window.client()["workspace"]["name"].startswith("special:")


def test_asking_to_be_minimised_again_is_heard_again(desk):
    window = desk.x11()
    mark = desk.bench.events.mark()
    for _ in range(2):
        window.command("iconify")
        window.wait(lambda c: c["workspace"]["name"].startswith("special:min-"), "minimised")
        desk.shell.call("minimize", "toggle", window.address)
        window.wait(lambda c: not c["workspace"]["name"].startswith("special:"), "brought back")
    assert len(minimize_requests(desk, window, mark)) == 2


def test_an_old_maximise_request_does_not_come_back_with_fullscreen(desk):
    window = desk.x11(width=800, height=500)
    window.command("netstate add maximized")
    window.wait(lambda c: "maximized" in c["tags"], "maximised")
    desk.restore(window)
    window.wait(lambda c: not c["tags"], "put back by the shell")

    window.command("netstate add fullscreen")
    window.wait(lambda c: c["fullscreen"] != 0, "fullscreen")
    window.command("netstate remove fullscreen")
    window.wait(lambda c: c["fullscreen"] == 0, "out of fullscreen")
    time.sleep(0.5)
    assert not window.client()["tags"], "not maximised again by the old request"
