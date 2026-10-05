-- Compositor rules of the experimental environment.

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

-- A maximised window meets the edges of the screen and a snapped one its
-- neighbour, so, as on Windows, neither has round corners, and a maximised
-- one has no border or shadow either. The shell tags the windows it places.
hl.window_rule({ match = { tag = "maximized" }, rounding = 0, border_size = 0, no_shadow = true })
hl.window_rule({ match = { tag = "snapped" }, rounding = 0 })

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

-- key -> { class, title, monitor, x, y, w, h }, positions relative to the monitor.
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
        -- class, title, monitor, x, y, w, h. A file written before titles were
        -- kept has no title field.
        local class, title, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)$")
        if not class then
            class, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)$")
            title = ""
        end
        -- One remembered by class alone for a shared class cannot be told
        -- apart from the others and is dropped.
        if class and not (SHARED_CLASSES[class] and title == "") then
            YUKI_GEOMETRY[keyOf(class, title)] = { class = class, title = title, monitor = monitor, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
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
        file:write(string.format("%s\t%s\t%s\t%d\t%d\t%d\t%d\n", g.class, g.title or "", g.monitor or "", g.x, g.y, g.w, g.h))
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

local function usableWindow(w)
    return usable(w.initial_class) and (not SHARED_CLASSES[w.initial_class] or usable(w.initial_title))
end

readGeometry()
for key in pairs(YUKI_GEOMETRY) do
    -- A reload rebuilds everything, and an application already open must not
    -- have its rule waiting for a second window.
    if openCount(key) == 0 then
        arm(key)
    end
end

-- An X11 application places and sizes its own window, Steam among them, which
-- comes back as large as it was, so it is not remembered here, and a place
-- remembered for one before is dropped as it opens. A window rule cannot tell
-- the two kinds apart: its xwayland match is not acted on.
hl.on("window.open", function(w)
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
    local scale = m.scale or 1
    local turned = (m.transform or 0) % 2 == 1
    local width = (turned and m.height or m.width) / scale
    local height = (turned and m.width or m.height) / scale
    local r = type(m.reserved) == "table" and m.reserved or {}
    return w.size.x >= width - (r.left or 0) - (r.right or 0) - 8
        and w.size.y >= height - (r.top or 0) - (r.bottom or 0) - 8
end

hl.on("window.close", function(w)
    local placed = YUKI_PLACED[w.address]
    YUKI_PLACED[w.address] = nil
    if not usableWindow(w) or w.xwayland then
        return
    end
    local key = windowKey(w)
    if openCount(key, w.address) > 0 then
        return
    end
    -- One told it is maximised, or as large as the work area, that the shell
    -- did not report as placed is the size of the screen and not where it
    -- stood, so what was remembered before is kept. Remembered, it opened as
    -- large as the screen again next time, as an ordinary window.
    local maximized = not placed and (w.fullscreen_client ~= 0 or coversWorkArea(w))
    if w.floating and w.fullscreen == 0 and not maximized and w.monitor and w.at and w.size then
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
