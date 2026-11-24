-- Compositor rules of Blueberry.

-- Qt programs pick files through the portal, the shell's own picker, as
-- everything else here does. The KDE platform theme's own dialog was kept for
-- them at first, and turned out the worse of the two in use. The theme reads
-- this once, as a program starts. Listed for uwsm to hand on to the user's
-- services, where programs started from the shell take their environment
-- from: as the session starts, and again when the shell switches to here.
hl.env("PLASMA_INTEGRATION_USE_PORTAL", "1")
hl.env("UWSM_FINALIZE_VARNAMES", "PLASMA_INTEGRATION_USE_PORTAL")

-- A desktop of overlapping windows, not a tiling one: everything opens floating.
hl.window_rule({ match = { class = ".*" }, float = true })

-- Focus by click, as on Windows. The pointer still reaches what it is over,
-- scrolling included, but only a click moves the keyboard. With focus
-- following the pointer, the window a person meant was lost on the way to the
-- dock: crossing another window took focus to it, so a click on the first
-- window's button brought it up again instead of minimising it.
hl.config({ input = { follow_mouse = 2 } })

-- Maximising is the shell's, as on Windows: a floating window given the work
-- area and put back where it was. Hyprland's own maximise is a kind of
-- fullscreen that only one window per workspace can have and that is not
-- raised over floating windows, so it is suppressed, and a window's request to
-- maximise reaches the shell through the minimize plugin instead.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Window shadows after Windows 11, where a window stands at elevation 128:
-- Fluent blurs such a shadow by 128 and drops it by 64 at about a quarter
-- opacity, which leaves roughly half of that at the window's lower edge,
-- fading out over a long way. Hyprland's shadow is at full colour right at the
-- edge, so the colour is that half and the falloff slow. It draws one shadow
-- of one size for every window, so the window in front is told apart by depth
-- of colour alone, those behind it casting half as dark a shadow.
hl.config({
    decoration = {
        shadow = {
            enabled = true,
            range = 96,
            render_power = 2,
            offset = { 0, 32 },
            color = "rgba(00000024)",
            color_inactive = "rgba(00000012)",
        },
    },
})

-- Against an attached dock a maximised window meets the edges of the screen
-- and a snapped one its neighbour, so, as on Windows, neither has round
-- corners, and a maximised one has no border or shadow either. With the dock
-- standing off the edge they stand off the edges as well, and are drawn as
-- any other window. The shell tags the windows it places by which it is.
hl.window_rule({ match = { tag = "square" }, rounding = 0 })
hl.window_rule({ match = { tag = "bare" }, border_size = 0, no_shadow = true })

-- A maximised window fills its place until it is put back, as on Windows: its
-- border neither resizes it nor shows the resize cursor. Named to the plugins
-- that hold it, when they are loaded; an environment that names nothing holds
-- nothing.
if hl.plugin.minimize then
    hl.config({ plugin = { minimize = { fixed_size_tag = "maximized" } } })
end
if hl.plugin.border_resize then
    hl.config({ plugin = { border_resize = { fixed_size_tag = "maximized" } } })
end

-- A Wine window is told it is maximised only while the shell has it maximised.
-- Hyprland tells every Wayland window it is maximised, so that a GTK window
-- leaves out the margin it draws for a shadow, and Wine, which draws no such
-- thing, takes it literally and asks back to be maximised: a splash screen
-- came up filling the screen, and a fullscreen game asked dozens of times a
-- second. Told the truth, its requests are taken at their word by the shell.
if hl.plugin.minimize and hl.plugin.minimize.literal_class_suffix then
    hl.plugin.minimize.literal_class_suffix(".exe")
end

-- Blur behind the dock, as its settings ask. The shell calls this as it
-- starts, whenever the setting changes and after every reload, which builds
-- the rules anew. A pixel at or below the given opacity is not blurred, which
-- keeps the shadow round a floating dock clear of it, and what is behind the
-- dock is blurred as it is, windows included, rather than the wallpaper alone.
-- A reload builds every rule anew, so one kept from before it is gone.
YUKI_DOCK_BLUR_RULE = nil
function YUKI_SET_DOCK_BLUR(enabled, ignoreAlpha)
    if YUKI_DOCK_BLUR_RULE then
        YUKI_DOCK_BLUR_RULE:set_enabled(false)
        YUKI_DOCK_BLUR_RULE = nil
    end
    if enabled then
        YUKI_DOCK_BLUR_RULE = hl.layer_rule({ match = { namespace = "^(quickshell:dock)$" }, blur = true, ignore_alpha = ignoreAlpha, xray = false })
    end
end
-- Nothing is blurred behind the flyouts that open from the dock, quick
-- settings, notifications and menus among them. The shared rules blur the
-- popups of every shell layer. These flyouts are opaque, so that blur only
-- showed while one faded in or out, as a smeared wash through the panel.
hl.layer_rule({ match = { namespace = "^(quickshell:dock)$" }, blur_popups = false })

-- What an X11 application may do with its window from a title bar of its own,
-- told to it as it is honoured here. Minimising and maximising are the
-- shell's. A maximised window carries the tag that holds its size, and one
-- pulled away is put back by the shell, so it is neither moved nor resized.
-- Nothing tiles here, and a window that did would be the layout's to place.
if hl.plugin.minimize and hl.plugin.minimize.allowed_actions then
    hl.plugin.minimize.allowed_actions({
        tiled = { "minimize", "maximize", "fullscreen", "close" },
        floating = { "move", "resize", "minimize", "maximize", "fullscreen", "close" },
        held = { "minimize", "maximize", "fullscreen", "close" },
    })
end

-- With nothing tiled, the key that switches a window between floating and
-- tiled maximises it instead and puts it back where it was, the way a double
-- click on a title bar does on Windows.
hl.bind("SUPER + ALT + Space", hl.dsp.global("quickshell:maximizeToggle"), { description = "Window: Maximize/Restore" })

-- The keys Windows places windows with. Super and an arrow snaps the window to
-- that side, maximises it, or steps it back down to where it stood and then
-- to the dock. Super+D shows the desktop and brings the windows back.
for _, arrow in ipairs({ "Left", "Right", "Up", "Down" }) do
    hl.bind("SUPER + " .. arrow, hl.dsp.global("quickshell:snap" .. arrow), { description = "Window: Snap " .. arrow })
end
hl.bind("SUPER + D", hl.dsp.global("quickshell:showDesktop"), { description = "Window: Show desktop" })

-- The welcome, opened by the shell on the first start, again by hand.
hl.bind("SHIFT + SUPER + ALT + Slash", hl.dsp.exec_cmd("qs -p $HOME/.config/quickshell/$qsConfig/blueberryWelcome.qml"))

-- Print Screen opens the snipping tool, as on Windows 11, rather than putting
-- the whole screen on the clipboard. Win+Shift+S and Win+Shift+R open it too,
-- for a picture and for a video, through the shell's shortcuts the shared
-- binds already name. Ctrl+Print Screen still saves the whole screen.
hl.unbind("Print")
hl.bind("Print", hl.dsp.global("quickshell:snipOpen"), { description = "Utilities: Snipping tool" })
-- The frozen screens come up as they are, at once, as on Windows. Faded and
-- grown in as any other layer, the screen seemed to jump.
hl.layer_rule({ match = { namespace = "^(quickshell:snip)$" }, no_anim = true })
-- The game bar fades in by itself, the bar and its widgets in place, as on
-- Windows, rather than growing in as one layer. The game is blurred behind its
-- glass and only dimmed around it: the glass is more opaque than the
-- threshold, the dimming with a shadow over it is less.
hl.layer_rule({ match = { namespace = "^(quickshell:gamebar)$" }, no_anim = true, blur = true, ignore_alpha = 0.6, xray = false })

-- Alt+Tab, drawn by the shell. Letting go of Alt is what picks the window, and
-- a key pressed before the switcher took the keyboard is not released to it,
-- so letting go of Alt is bound. Non-consuming: a bind on the release of a key
-- otherwise swallows the key's press as well, and Alt stopped reaching
-- applications at all. Transparent: Hyprland lets the release of a key fire
-- only if no other key was pressed meanwhile, Tab say, and spares transparent
-- binds from that, and without it the switcher waited for good. Both were
-- measured on the test bench, not taken from the source alone. Every release
-- of Alt reaches the shell, which does nothing with it unless a switch is
-- under way.
hl.bind("ALT + Tab", hl.dsp.global("quickshell:altTabNext"), { description = "Shell: Switch windows" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("quickshell:altTabPrevious"))
for _, key in ipairs({ "ALT_L", "ALT_R" }) do
    hl.bind(key, hl.dsp.global("quickshell:altTabCommit"), { ignore_mods = true, release = true, non_consuming = true, transparent = true })
end
-- A bind on the release of a modifier does not fire while another key is down,
-- and a hand lets go of Alt with Tab still pressed as often as not: the switcher
-- then stayed up until Alt was next tapped. The key event comes whatever else is
-- held. The bind stays for an Alt moved to another key, which the codes of the
-- two Alt keys here do not know of.
local ALT_KEYCODES = { [64] = true, [108] = true }
hl.on("input.keyboard.key", function(keycode, _, state)
    if state == 0 and ALT_KEYCODES[keycode] then
        hl.dispatch(hl.dsp.global("quickshell:altTabCommit"))
    end
end)

-- Windows come back where they were left.
--
-- On Wayland an application cannot place its own window, so remembering where
-- it stood is the compositor's job. When the last window of an application
-- closes, its place on the monitor and its size are written down, and the next
-- first window of that application opens there. Only the first: a second
-- window, or a dialog, which carries the same class, opens the usual way, and
-- a dialog closing while its application is still open is not what gets
-- remembered.
--
-- The rule for each application is armed only while none of its windows is
-- open, so it reaches the one window it is meant for and no other. Rules act
-- before the first frame, so a window does not jump into place.
--
-- The state is plain lines of text, not lua, so reading it back never runs
-- whatever the file happens to hold.

local stateDir = HOME .. "/.local/state/yuki"
local geometryPath = stateDir .. "/window-geometry"

-- Classes that more than one program shares, told apart by their first title.
-- Every Quickshell window, the settings and the file picker among them, is
-- org.quickshell, and remembered by class alone one of them opened where
-- another had been closed.
local SHARED_CLASSES = { ["org.quickshell"] = true }

-- Windows that open as they ask, never where they last stood: the welcome
-- sizes itself to the screen it opens on, and a size remembered from a screen
-- in another mode kept it a third of a larger one. By key, as below.
local NOT_REMEMBERED = { ["org.quickshell\tBlueberry Welcome"] = true }

-- A window closed this many seconds or less after it opened is not
-- remembered: a splash screen closes before its application's main window
-- opens, and was taken for the last window of that application, so every
-- later launch put the splash where it had once been. A global, so the test
-- bench can shorten it.
YUKI_GEOMETRY_MIN_LIFE = 10
-- address -> when the window opened, by os.time. Emptied by a reload, after
-- which a window already open counts as one that has lived long enough.
YUKI_OPENED = {}

-- key -> { class, title, monitor, x, y, w, h, centered }, positions relative
-- to the monitor. A window that stood in the middle of the work area is
-- remembered as centred and comes back in the middle of whatever screen it
-- opens on: kept in pixels alone, one centred on a 1920x1080 screen came back
-- off centre once that screen ran at 2560x1440.
-- Read afresh from the file on every load: the table outlives a reload, and
-- one left by an older version of this file is in a shape this one does not
-- read.
YUKI_GEOMETRY = {}
-- key -> the armed rule for it.
YUKI_GEOMETRY_RULES = {}
-- address -> { zone, x, y, w, h }, global: how a window the shell has
-- maximised or snapped is placed and where it stood before it was, told by the
-- shell as it places one. Such a window is remembered as it stood, the way
-- Windows keeps a window's restored place, not as half the screen or all of
-- it, and a shell started anew reads its placements back from here. A reload
-- starts lua afresh and empties it, and the shell tells it again as it fits its
-- placed windows to the screen after one.
YUKI_PLACED = {}

local function keyOf(class, title)
    if SHARED_CLASSES[class] then
        return class .. "\t" .. (title or "")
    end
    return class
end

local function windowKey(w)
    return keyOf(w.initial_class, w.initial_title)
end

local function readGeometry()
    local file = io.open(geometryPath, "r")
    if not file then
        return
    end
    for line in file:lines() do
        -- class, title, monitor, x, y, w, h, and "centered" after them for a
        -- window that stood in the middle. A file written before titles were
        -- kept has no title field.
        local centered = false
        local class, title, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)\tcentered$")
        if class then
            centered = true
        else
            class, title, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)$")
        end
        if not class then
            class, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)$")
            title = ""
        end
        -- One remembered by class alone for a shared class cannot be told
        -- apart from the others and is dropped.
        if class and not (SHARED_CLASSES[class] and title == "") and not NOT_REMEMBERED[keyOf(class, title)] then
            YUKI_GEOMETRY[keyOf(class, title)] = { class = class, title = title, monitor = monitor, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h), centered = centered }
        end
    end
    file:close()
end

local function writeGeometry()
    -- The folder is made only when the file cannot be opened without it:
    -- os.execute forks a shell, and this runs on the compositor's own thread
    -- as a window closes.
    local file = io.open(geometryPath .. ".tmp", "w")
    if not file then
        os.execute("mkdir -p '" .. stateDir .. "'")
        file = io.open(geometryPath .. ".tmp", "w")
    end
    if not file then
        return
    end
    for _, g in pairs(YUKI_GEOMETRY) do
        file:write(string.format("%s\t%s\t%s\t%d\t%d\t%d\t%d%s\n", g.class, g.title or "", g.monitor or "", g.x, g.y, g.w, g.h,
            g.centered and "\tcentered" or ""))
    end
    file:close()
    os.rename(geometryPath .. ".tmp", geometryPath)
end

-- A class is matched as a regular expression, so what it contains is taken
-- literally.
local function literal(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%{%}|\\]", "\\%0"))
end

local function arm(key)
    local g = YUKI_GEOMETRY[key]
    if not g then
        return
    end
    if YUKI_GEOMETRY_RULES[key] then
        YUKI_GEOMETRY_RULES[key]:set_enabled(false)
    end
    local match = { initial_class = "^(" .. literal(g.class) .. ")$" }
    if SHARED_CLASSES[g.class] then
        match.initial_title = "^(" .. literal(g.title) .. ")$"
    end
    -- Measured against the monitor the window opens on, which need not be
    -- the one it was closed on: a place on a wide screen would put it out of
    -- reach on a narrow one. The place is worked out from the remembered size,
    -- since the move is reckoned before the size rule has resized the window.
    -- Written without spaces, which part x from y.
    local w = string.format("min(%d,monitor_w)", g.w)
    local h = string.format("min(%d,monitor_h)", g.h)
    if g.centered then
        YUKI_GEOMETRY_RULES[key] = hl.window_rule({ match = match, size = w .. " " .. h, center = true })
        return
    end
    YUKI_GEOMETRY_RULES[key] = hl.window_rule({
        match = match,
        size = w .. " " .. h,
        move = string.format("max(0,min(%d,monitor_w-%s)) max(0,min(%d,monitor_h-%s))", g.x, w, g.y, h),
    })
end

local function disarm(key)
    if YUKI_GEOMETRY_RULES[key] then
        YUKI_GEOMETRY_RULES[key]:set_enabled(false)
    end
end

local function openCount(key, except)
    local count = 0
    for _, w in ipairs(hl.get_windows()) do
        if windowKey(w) == key and w.address ~= except then
            count = count + 1
        end
    end
    return count
end

-- Tabs and line breaks would break the file, and no real class has them.
local function usable(text)
    return text and #text > 0 and not text:find("[\t\n]")
end

-- The part of a monitor windows are placed in, in global coordinates and
-- logical pixels: the monitor less what the dock and other panels reserve.
local function workAreaOf(m)
    local scale = m.scale or 1
    local turned = (m.transform or 0) % 2 == 1
    local width = (turned and m.height or m.width) / scale
    local height = (turned and m.width or m.height) / scale
    local r = type(m.reserved) == "table" and m.reserved or {}
    return {
        x = m.x + (r.left or 0),
        y = m.y + (r.top or 0),
        w = width - (r.left or 0) - (r.right or 0),
        h = height - (r.top or 0) - (r.bottom or 0),
    }
end

local function usableWindow(w)
    return usable(w.initial_class) and (not SHARED_CLASSES[w.initial_class] or usable(w.initial_title))
        and not NOT_REMEMBERED[windowKey(w)]
end

readGeometry()
for key in pairs(YUKI_GEOMETRY) do
    -- A reload rebuilds everything, and an application already open must not
    -- have its rule waiting for a second window.
    if openCount(key) == 0 then
        arm(key)
    end
end

-- Puts a window already open where its application last stood, as the armed
-- rule puts its first window as it opens, for one this environment takes over
-- from another as it comes up. False when nothing is remembered for it.
function YUKI_PLACE_REMEMBERED(address)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == address then
            local g = usableWindow(w) and YUKI_GEOMETRY[windowKey(w)]
            local m = w.monitor
            if not g or not m then
                return false
            end
            local width = math.min(g.w, m.width)
            local height = math.min(g.h, m.height)
            local target = "address:" .. address
            hl.dispatch(hl.dsp.window.resize({ window = target, x = width, y = height }))
            if g.centered then
                local area = workAreaOf(m)
                hl.dispatch(hl.dsp.window.move({ window = target, x = math.floor(area.x + (area.w - width) / 2), y = math.floor(area.y + (area.h - height) / 2) }))
            else
                hl.dispatch(hl.dsp.window.move({ window = target, x = m.x + math.max(0, math.min(g.x, m.width - width)), y = m.y + math.max(0, math.min(g.y, m.height - height)) }))
            end
            return true
        end
    end
    return false
end

-- An X11 application places and sizes its own window, Steam among them, which
-- comes back as large as it was, so it is not remembered here, and a place
-- remembered for one before is dropped as it opens. A window rule cannot tell
-- the two kinds apart: its xwayland match is not acted on.
hl.on("window.open", function(w)
    YUKI_OPENED[w.address] = os.time()
    if usableWindow(w) then
        local key = windowKey(w)
        disarm(key)
        if w.xwayland and YUKI_GEOMETRY[key] then
            YUKI_GEOMETRY[key] = nil
            YUKI_GEOMETRY_RULES[key] = nil
            writeGeometry()
        end
    end
end)

-- Whether a window covers the work area of its monitor, give or take a few
-- pixels, as the shell judges it when it maximises a window that opens so.
local function coversWorkArea(w)
    local m = w.monitor
    if not m or not w.size then
        return false
    end
    local area = workAreaOf(m)
    return w.size.x >= area.w - 8 and w.size.y >= area.h - 8
end

-- Whether a window stands in the middle of the work area, give or take the
-- rounding of an odd size.
local function centeredIn(area, at, size)
    return math.abs(at.x + size.x / 2 - (area.x + area.w / 2)) <= 4
        and math.abs(at.y + size.y / 2 - (area.y + area.h / 2)) <= 4
end

-- Whether another window stands over part of a floating one: one later in the
-- list Hyprland draws them in, or a pinned one, or one fullscreen on its
-- workspace. Global, so the tests can ask.
function YUKI_COVERED(address)
    local windows = hl.get_windows()
    local w
    for _, candidate in ipairs(windows) do
        if candidate.address == address then
            w = candidate
        end
    end
    if not w or not w.floating or not w.workspace or not w.at or not w.size then
        return false
    end
    local past = false
    for _, o in ipairs(windows) do
        if o.address == address then
            past = true
        elseif o.workspace and o.workspace.id == w.workspace.id and o.at and o.size
            and (o.fullscreen ~= 0 or o.pinned or (o.floating and past))
            and o.at.x < w.at.x + w.size.x and w.at.x < o.at.x + o.size.x
            and o.at.y < w.at.y + w.size.y and w.at.y < o.at.y + o.size.y then
            return true
        end
    end
    return false
end

hl.on("window.close", function(w)
    -- Hyprland draws windows going away after every floating one, whatever
    -- stood over them, so one closed from under others faded over them. This
    -- runs before the picture of it is taken, and it takes none of a window
    -- that is not to be animated.
    if YUKI_COVERED(w.address) then
        hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. w.address, prop = "no_anim", value = "1" }))
    end
    local placed = YUKI_PLACED[w.address]
    YUKI_PLACED[w.address] = nil
    local opened = YUKI_OPENED[w.address]
    YUKI_OPENED[w.address] = nil
    if not usableWindow(w) or w.xwayland then
        return
    end
    local key = windowKey(w)
    if openCount(key, w.address) > 0 then
        return
    end
    -- What was remembered before is kept, and armed again below.
    local shortLived = opened ~= nil and os.time() - opened <= YUKI_GEOMETRY_MIN_LIFE
    -- One told it is maximised, or as large as the work area, that the shell
    -- did not report as placed is the size of the screen and not where it
    -- stood, so what was remembered before is kept. Remembered, it opened as
    -- large as the screen again next time, as an ordinary window.
    local maximized = not placed and (w.fullscreen_client ~= 0 or coversWorkArea(w))
    if not shortLived and w.floating and w.fullscreen == 0 and not maximized and w.monitor and w.at and w.size then
        local m = w.monitor
        local at = placed and { x = placed.x, y = placed.y } or w.at
        local size = placed and { x = placed.w, y = placed.h } or w.size
        -- Kept on the monitor, so a window left hanging off an edge does not
        -- come back with part of it out of reach.
        local width = math.min(size.x, m.width)
        local height = math.min(size.y, m.height)
        YUKI_GEOMETRY[key] = {
            class = w.initial_class,
            title = SHARED_CLASSES[w.initial_class] and w.initial_title or "",
            monitor = m.name,
            x = math.max(0, math.min(at.x - m.x, m.width - width)),
            y = math.max(0, math.min(at.y - m.y, m.height - height)),
            w = width,
            h = height,
            centered = centeredIn(workAreaOf(m), at, size),
        }
        writeGeometry()
    end
    arm(key)
end)

-- Touchpad gestures, as the settings have them. The shell writes them down,
-- one a line: fingers, direction and action, tab between, and reloads, since a
-- gesture once made cannot be taken back otherwise. Plain lines, as for the
-- places of windows, and only the actions named here are acted on. Before the
-- shell has written any, three fingers move the window under them and a pinch
-- makes it fullscreen, and four switch workspaces sideways.
-- Found by XDG_STATE_HOME, as the shell writes it: the test bench gives the
-- compositor and its shells a state folder of their own and leaves HOME the
-- person's.
local stateHome = os.getenv("XDG_STATE_HOME")
if not stateHome or stateHome == "" then
    stateHome = HOME .. "/.local/state"
end
local gesturesPath = stateHome .. "/yuki/gestures"

local GESTURE_DIRECTIONS = { swipe = true, horizontal = true, up = true, down = true, pinch = true }
-- Hyprland's own, and those the shell answers as global shortcuts.
local GESTURE_BUILTINS = { workspace = true, move = true, fullscreen = true }
local GESTURE_GLOBALS = {
    search = "searchToggle",
    showDesktop = "showDesktop",
    notifications = "dockNotifications",
    quickSettings = "dockQuickSettings",
    maximize = "maximizeToggle",
}

local function gestureAction(name)
    if GESTURE_BUILTINS[name] then
        return name
    end
    local global = GESTURE_GLOBALS[name]
    if global then
        return function()
            hl.dispatch(hl.dsp.global("quickshell:" .. global))
        end
    end
    return nil
end

local function readGestures()
    local file = io.open(gesturesPath, "r")
    if not file then
        return { { 3, "swipe", "move" }, { 3, "pinch", "fullscreen" }, { 4, "horizontal", "workspace" } }
    end
    local found = {}
    for line in file:lines() do
        local fingers, direction, action = line:match("^(%d)\t(%a+)\t(%a+)$")
        fingers = tonumber(fingers)
        if fingers and fingers >= 3 and fingers <= 5 and GESTURE_DIRECTIONS[direction] then
            found[#found + 1] = { fingers, direction, action }
        end
    end
    file:close()
    return found
end

for _, g in ipairs(readGestures()) do
    local action = gestureAction(g[3])
    if action then
        hl.gesture({ fingers = g[1], direction = g[2], action = action })
    end
end

-- The blur behind the dock as the shell last asked for it, built as the rules
-- load. Left to the shell alone, a reload left the dock unblurred until the
-- shell heard of it and asked again, and the blur blinked on every reload.
-- One line: 1 or 0, a tab, the opacity at or below which nothing is blurred.
do
    local file = io.open(stateHome .. "/yuki/dock-blur", "r")
    if file then
        local enabled, threshold = (file:read("*l") or ""):match("^([01])\t([%d.]+)$")
        file:close()
        if enabled then
            YUKI_SET_DOCK_BLUR(enabled == "1", tonumber(threshold))
        end
    end
end
