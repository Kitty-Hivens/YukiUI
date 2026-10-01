-- Compositor rules of the experimental environment.

-- A desktop of overlapping windows, not a tiling one: everything opens floating.
hl.window_rule({ match = { class = ".*" }, float = true })

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

-- class -> { monitor, x, y, w, h }, positions relative to the monitor.
YUKI_GEOMETRY = YUKI_GEOMETRY or {}
-- class -> the armed rule for it.
YUKI_GEOMETRY_RULES = {}

local function readGeometry()
    local file = io.open(geometryPath, "r")
    if not file then
        return
    end
    for line in file:lines() do
        local class, monitor, x, y, w, h = line:match("^([^\t]+)\t([^\t]*)\t(%-?%d+)\t(%-?%d+)\t(%d+)\t(%d+)$")
        if class then
            YUKI_GEOMETRY[class] = { monitor = monitor, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
        end
    end
    file:close()
end

local function writeGeometry()
    os.execute("mkdir -p '" .. stateDir .. "'")
    local file = io.open(geometryPath .. ".tmp", "w")
    if not file then
        return
    end
    for class, g in pairs(YUKI_GEOMETRY) do
        file:write(string.format("%s\t%s\t%d\t%d\t%d\t%d\n", class, g.monitor or "", g.x, g.y, g.w, g.h))
    end
    file:close()
    os.rename(geometryPath .. ".tmp", geometryPath)
end

-- A class is matched as a regular expression, so what it contains is taken
-- literally.
local function literal(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%{%}|\\]", "\\%0"))
end

local function arm(class)
    local g = YUKI_GEOMETRY[class]
    if not g then
        return
    end
    if YUKI_GEOMETRY_RULES[class] then
        YUKI_GEOMETRY_RULES[class]:set_enabled(false)
    end
    YUKI_GEOMETRY_RULES[class] = hl.window_rule({
        match = { initial_class = "^(" .. literal(class) .. ")$" },
        size = string.format("%d %d", g.w, g.h),
        move = string.format("%d %d", g.x, g.y),
    })
end

local function disarm(class)
    if YUKI_GEOMETRY_RULES[class] then
        YUKI_GEOMETRY_RULES[class]:set_enabled(false)
    end
end

local function openCount(class, except)
    local count = 0
    for _, w in ipairs(hl.get_windows()) do
        if w.initial_class == class and w.address ~= except then
            count = count + 1
        end
    end
    return count
end

-- Tabs and line breaks would break the file, and no real class has them.
local function usable(class)
    return class and #class > 0 and not class:find("[\t\n]")
end

readGeometry()
for class in pairs(YUKI_GEOMETRY) do
    -- A reload rebuilds everything, and an application already open must not
    -- have its rule waiting for a second window.
    if openCount(class) == 0 then
        arm(class)
    end
end

hl.on("window.open", function(w)
    if usable(w.initial_class) then
        disarm(w.initial_class)
    end
end)

hl.on("window.close", function(w)
    local class = w.initial_class
    if not usable(class) or openCount(class, w.address) > 0 then
        return
    end
    if w.floating and w.fullscreen == 0 and w.monitor and w.at and w.size then
        local m = w.monitor
        -- Kept on the monitor, so a window left hanging off an edge does not
        -- come back with part of it out of reach.
        local width = math.min(w.size.x, m.width)
        local height = math.min(w.size.y, m.height)
        YUKI_GEOMETRY[class] = {
            monitor = m.name,
            x = math.max(0, math.min(w.at.x - m.x, m.width - width)),
            y = math.max(0, math.min(w.at.y - m.y, m.height - height)),
            w = width,
            h = height,
        }
        writeGeometry()
    end
    arm(class)
end)
